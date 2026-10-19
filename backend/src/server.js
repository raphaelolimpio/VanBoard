require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { rateLimit } = require('express-rate-limit');
const { PrismaClient } = require('@prisma/client');
const { transactionDateFilter, isValidFinancialReceipt } = require('./financial_validation');

const prisma = new PrismaClient();
const app = express();
const PORT = Number(process.env.PORT || 3333);
const JWT_SECRET = process.env.JWT_SECRET;
const TOKEN_TTL = '12h';
const isProduction = process.env.NODE_ENV === 'production';
const trustProxyHops = process.env.TRUST_PROXY_HOPS;
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map(origin => origin.trim())
  .filter(Boolean);

if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET precisa estar definido com pelo menos 32 caracteres antes de iniciar a API.');
}
if (isProduction && !allowedOrigins.length) {
  throw new Error('ALLOWED_ORIGINS deve listar as origens HTTPS permitidas em produção.');
}
if (isProduction && allowedOrigins.some(origin => {
  try {
    const parsed = new URL(origin);
    return parsed.protocol !== 'https:' || parsed.origin !== origin;
  } catch {
    return true;
  }
})) {
  throw new Error('Todas as origens permitidas em produção devem usar HTTPS.');
}
if (trustProxyHops !== undefined && trustProxyHops !== '') {
  const parsedHops = Number(trustProxyHops);
  if (!Number.isInteger(parsedHops) || parsedHops < 0) {
    throw new Error('TRUST_PROXY_HOPS deve ser um inteiro não negativo.');
  }
  app.set('trust proxy', parsedHops);
}

const corsOptions = {
  origin(origin, callback) {
    if (!isProduction || !origin || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error('Origem não permitida.'));
  }
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '1mb' }));
const io = {
  to: () => ({ emit: () => {} }),
  use: () => {},
  on: () => {}
};

const loginRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  skipSuccessfulRequests: true,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { error: 'Muitas tentativas. Aguarde antes de tentar novamente.' }
});
const registrationRateLimit = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 5,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { error: 'Limite de cadastros atingido. Tente novamente mais tarde.' }
});

function issueToken(user) {
  return jwt.sign(
    { role: user.role, companyId: user.companyId, ownerId: user.ownerId },
    JWT_SECRET,
    { subject: user.id, expiresIn: TOKEN_TTL }
  );
}

function authenticate(req, res, next) {
  const header = req.get('authorization');
  const token = header && header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Autenticação necessária.' });

  try {
    req.user = jwt.verify(token, JWT_SECRET);
    return next();
  } catch {
    return res.status(401).json({ error: 'Sessão inválida ou expirada. Entre novamente.' });
  }
}

function requireOwner(req, res, next) {
  if (req.user.role !== 'OWNER') {
    return res.status(403).json({ error: 'Somente o proprietário pode executar esta ação.' });
  }
  return next();
}

async function requireActiveDriver(req, res, next) {
  if (req.user.role !== 'DRIVER') {
    return res.status(403).json({ error: 'Área exclusiva do motorista.' });
  }
  const driver = await prisma.driver.findFirst({
    where: { id: req.user.sub, active: true }
  });
  if (!driver) return res.status(401).json({ error: 'Conta de motorista inativa.' });
  req.driver = driver;
  return next();
}

async function companyForUser(user, companyId) {
  if (user.role === 'OWNER') {
    return prisma.company.findFirst({ where: { id: companyId, ownerId: user.sub } });
  }
  if (user.companyId === companyId) {
    const driver = await prisma.driver.findFirst({
      where: { id: user.sub, companyId, active: true },
      select: { id: true }
    });
    if (!driver) return null;
    return prisma.company.findUnique({ where: { id: companyId } });
  }
  return null;
}

async function accessibleVehicle(user, vehicleId) {
  const vehicle = await prisma.vehicle.findUnique({
    where: { id: vehicleId },
    select: { id: true, companyId: true, defaultDriverId: true }
  });
  if (!vehicle) return null;
  if (user.role === 'OWNER') {
    const company = await companyForUser(user, vehicle.companyId);
    return company ? vehicle : null;
  }
  if (vehicle.defaultDriverId !== user.sub) return null;
  const driver = await prisma.driver.findFirst({
    where: { id: user.sub, companyId: vehicle.companyId, active: true },
    select: { id: true }
  });
  return driver ? vehicle : null;
}

function finiteNumber(value, name, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    throw new Error(`${name} está fora do intervalo válido.`);
  }
  return number;
}

function optionalCoordinate(value, name, min, max) {
  if (value == null || value === '') return null;
  return finiteNumber(value, name, min, max);
}

function distanceMeters(a, b) {
  const radians = value => value * Math.PI / 180;
  const earthRadius = 6371000;
  const dLat = radians(b.latitude - a.latitude);
  const dLon = radians(b.longitude - a.longitude);
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) *
    Math.sin(dLon / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function locationIsFresh(location) {
  return Boolean(location && Date.now() - location.updatedAt.getTime() <= 5 * 60 * 1000);
}

function createAccessCode() {
  return crypto.randomBytes(9).toString('base64url');
}

function hashAccessCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

async function monitorActiveRunLocations() {
  const runs = await prisma.serviceRun.findMany({
    where: { status: 'ACTIVE' },
    include: { vehicle: { select: { location: true } } },
    take: 500
  });
  const staleBefore = Date.now() - 3 * 60 * 1000;
  for (const run of runs) {
    if (run.vehicle.location && run.vehicle.location.updatedAt.getTime() >= staleBefore) continue;
    const existing = await prisma.vehicleAlert.findFirst({
      where: {
        serviceRunId: run.id,
        kind: 'GPS_SEM_SINAL',
        resolvedAt: null
      },
      select: { id: true }
    });
    if (!existing) {
      await prisma.vehicleAlert.create({
        data: {
          companyId: run.companyId,
          serviceRunId: run.id,
          vehicleId: run.vehicleId,
          kind: 'GPS_SEM_SINAL',
          message: 'Não recebemos uma posição GPS recente desta rota.'
        }
      });
    }
  }
}

async function nearestAvailableVehicle(companyId, brokenVehicleId, origin, excludedIds = []) {
  const since = new Date(Date.now() - 5 * 60 * 1000);
  const now = new Date();
  const vehicles = await prisma.vehicle.findMany({
    where: {
      companyId,
      id: { not: brokenVehicleId, notIn: excludedIds },
      status: 'PARADO',
      purposes: { has: 'ESCOLAR' },
      defaultDriver: { active: true, status: 'DISPONIVEL' },
      trips: {
        none: {
          status: 'AGENDADO',
          departureDate: { lte: now },
          returnDate: { gte: now }
        }
      },
      location: { is: { updatedAt: { gte: since } } }
    },
    include: {
      location: true,
      defaultDriver: { select: { id: true, name: true } },
      students: { where: { active: true }, select: { id: true } }
    }
  });
  return vehicles
    .filter(vehicle => vehicle.capacity > vehicle.students.length)
    .map(vehicle => ({
      ...vehicle,
      distanceMeters: distanceMeters(origin, vehicle.location)
    }))
    .sort((a, b) => a.distanceMeters - b.distanceMeters)[0] || null;
}

async function issueNextEmergencyOffer(request, excludedIds = []) {
  const activeRequest = await prisma.emergencyRequest.findFirst({
    where: { id: request.id, status: 'OPEN' },
    select: { id: true }
  });
  if (!activeRequest) return null;

  const origin = await prisma.vehicleLocation.findUnique({
    where: { vehicleId: request.brokenVehicleId }
  });
  if (!origin) return null;
  const candidate = await nearestAvailableVehicle(
    request.companyId,
    request.brokenVehicleId,
    origin,
    excludedIds
  );
  if (!candidate) return null;

  const offer = await prisma.emergencyOffer.create({
    data: {
      requestId: request.id,
      vehicleId: candidate.id,
      distanceMeters: candidate.distanceMeters
    },
    include: {
      request: { include: { student: { select: { id: true, name: true, pickupAddr: true } } } },
      vehicle: { select: { id: true, plate: true, model: true } }
    }
  });
  const stillOpen = await prisma.emergencyRequest.findFirst({
    where: { id: request.id, status: 'OPEN' },
    select: { id: true }
  });
  if (!stillOpen) {
    await prisma.emergencyOffer.updateMany({
      where: { id: offer.id, status: 'PENDING' },
      data: { status: 'EXPIRED', respondedAt: new Date() }
    });
    return null;
  }

  io.to(`driver:${candidate.defaultDriver.id}`).emit('emergency:offer', offer);
  io.to(`company:${request.companyId}`).emit('emergency:created', {
    requestId: request.id,
    offerId: offer.id,
    candidateVehicleId: candidate.id
  });
  return offer;
}

async function consumeTripCredit(tx, student, count) {
  if (student.billingType !== 'POR_VIAGEM') return 0;
  const result = await tx.student.updateMany({
    where: { id: student.id, active: true, tripCredits: { gte: count } },
    data: { tripCredits: { decrement: count } }
  });
  if (result.count !== 1) throw new Error('Aluno sem créditos suficientes para esta chamada.');
  return count;
}

io.use(async (socket, next) => {
  const token = socket.handshake.auth && socket.handshake.auth.token;
  if (!token) return next(new Error('Autenticação necessária.'));
  try {
    socket.user = jwt.verify(token, JWT_SECRET);
    if (socket.user.role === 'DRIVER') {
      const driver = await prisma.driver.findFirst({
        where: { id: socket.user.sub, active: true },
        select: { companyId: true }
      });
      if (!driver || driver.companyId !== socket.user.companyId) {
        return next(new Error('Conta de motorista inativa.'));
      }
    }
    return next();
  } catch (error) {
    return next(error instanceof jwt.JsonWebTokenError
      ? new Error('Sessão inválida ou expirada.')
      : error);
  }
});

io.on('connection', async socket => {
  const { user } = socket;
  if (user.companyId) socket.join(`company:${user.companyId}`);
  if (user.role === 'DRIVER') {
    socket.join(`driver:${user.sub}`);
    const vehicle = await prisma.vehicle.findFirst({
      where: { defaultDriverId: user.sub },
      select: { id: true }
    });
    if (vehicle) socket.join(`vehicle:${vehicle.id}`);
  }
});

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/health/ready', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return res.json({ status: 'ready' });
  } catch (error) {
    console.error('Banco indisponível no teste de prontidão:', error);
    return res.status(503).json({ status: 'unavailable' });
  }
});

app.post('/auth/register-owner', registrationRateLimit, async (req, res) => {
  try {
    const { name, email, password, companyName, cnpj } = req.body;
    if (![name, email, password, companyName].every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Informe nome, e-mail, senha e nome da empresa.' });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'A senha precisa ter pelo menos 8 caracteres.' });
    }
    const normalizedEmail = email.trim().toLowerCase();
    if (await prisma.driver.findUnique({ where: { email: normalizedEmail }, select: { id: true } })) {
      return res.status(409).json({ error: 'E-mail já vinculado a uma conta de motorista.' });
    }
    const passwordHash = await bcrypt.hash(password, 12);
    const owner = await prisma.owner.create({
      data: {
        name: name.trim(),
        email: normalizedEmail,
        passwordHash,
        companies: { create: { name: companyName.trim(), cnpj: cnpj?.trim() || null } }
      },
      include: { companies: { select: { id: true, name: true } } }
    });
    const company = owner.companies[0];
    const user = { id: owner.id, role: 'OWNER', ownerId: owner.id, companyId: company.id };
    return res.status(201).json({
      token: issueToken(user),
      user: { id: owner.id, name: owner.name, email: owner.email, role: user.role, company }
    });
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'E-mail ou CNPJ já cadastrado.' });
    console.error('Falha ao criar proprietário:', error);
    return res.status(400).json({ error: 'Não foi possível criar a conta.' });
  }
});

app.post('/auth/login', loginRateLimit, async (req, res) => {
  try {
    const email = typeof req.body.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (!email || !password) return res.status(400).json({ error: 'Informe e-mail e senha.' });

    const owner = await prisma.owner.findUnique({
      where: { email },
      include: { companies: { select: { id: true, name: true } } }
    });
    if (owner) {
      if (!(await bcrypt.compare(password, owner.passwordHash))) {
        return res.status(401).json({ error: 'E-mail ou senha incorretos.' });
      }
      if (!owner.companies.length) return res.status(409).json({ error: 'Conta sem empresa vinculada.' });
      const company = owner.companies[0];
      const user = { id: owner.id, role: 'OWNER', ownerId: owner.id, companyId: company.id };
      return res.json({
        token: issueToken(user),
        user: { id: owner.id, name: owner.name, email: owner.email, role: user.role, company }
      });
    }

    const driver = await prisma.driver.findUnique({
      where: { email },
      include: { company: { select: { id: true, name: true } } }
    });
    if (!driver || !driver.active || !driver.passwordHash ||
        !(await bcrypt.compare(password, driver.passwordHash))) {
      return res.status(401).json({ error: 'E-mail ou senha incorretos.' });
    }
    const user = { id: driver.id, role: 'DRIVER', companyId: driver.companyId };
    return res.json({
      token: issueToken(user),
      user: {
        id: driver.id,
        name: driver.name,
        email: driver.email,
        role: user.role,
        company: driver.company
      }
    });
  } catch (error) {
    console.error('Falha no login:', error);
    return res.status(500).json({ error: 'Não foi possível entrar agora.' });
  }
});

app.post('/companies/:companyId/driver-invitations', authenticate, requireOwner, async (req, res) => {
  try {
    const { name, cnh, phone, email, vehicleId } = req.body;
    if (![name, cnh, phone, email].every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Preencha nome, CNH, telefone e e-mail.' });
    }
    const companyId = req.params.companyId;
    if (!(await companyForUser(req.user, companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const normalizedEmail = email.trim().toLowerCase();
    if (await prisma.owner.findUnique({ where: { email: normalizedEmail }, select: { id: true } })) {
      return res.status(409).json({ error: 'E-mail já vinculado a uma conta de proprietário.' });
    }
    if (vehicleId && !(await prisma.vehicle.findFirst({
      where: { id: vehicleId, companyId, defaultDriverId: null }
    }))) {
      return res.status(400).json({ error: 'Veículo inválido ou já atribuído a outro motorista.' });
    }
    const code = createAccessCode();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const result = await prisma.$transaction(async tx => {
      const driver = await tx.driver.create({
        data: {
          companyId,
          name: name.trim(),
          cnh: cnh.trim(),
          phone: phone.trim(),
          email: normalizedEmail,
          cnhCategory: typeof req.body.cnhCategory === 'string' ? req.body.cnhCategory : 'D',
          passwordHash: null,
          ...(vehicleId ? { vehicles: { connect: [{ id: vehicleId }] } } : {})
        },
        select: { id: true, name: true, email: true, phone: true }
      });
      if (vehicleId) {
        await tx.vehicle.update({ where: { id: vehicleId }, data: { defaultDriverId: driver.id } });
      }
      await tx.driverInvite.create({
        data: { companyId, driverId: driver.id, codeHash: hashAccessCode(code), expiresAt }
      });
      return driver;
    });
    res.status(201).json({ driver: result, activationCode: code, expiresAt });
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'E-mail ou veículo já cadastrado.' });
    console.error('Falha ao criar convite do motorista:', error);
    res.status(400).json({ error: 'Não foi possível criar o convite do motorista.' });
  }
});

app.post('/auth/driver-invitations/accept', loginRateLimit, async (req, res) => {
  try {
    const code = typeof req.body.code === 'string' ? req.body.code.trim() : '';
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (!code || password.length < 8) {
      return res.status(400).json({ error: 'Informe o código e uma senha com pelo menos 8 caracteres.' });
    }
    const invite = await prisma.driverInvite.findFirst({
      where: {
        codeHash: hashAccessCode(code),
        acceptedAt: null,
        revokedAt: null,
        expiresAt: { gt: new Date() }
      },
      include: { driver: { include: { company: { select: { id: true, name: true } } } } }
    });
    if (!invite || !invite.driver.active) {
      return res.status(400).json({ error: 'Convite inválido, expirado ou já utilizado.' });
    }
    const passwordHash = await bcrypt.hash(password, 12);
    await prisma.$transaction(async tx => {
      const claimed = await tx.driverInvite.updateMany({
        where: {
          id: invite.id,
          acceptedAt: null,
          revokedAt: null,
          expiresAt: { gt: new Date() }
        },
        data: { acceptedAt: new Date() }
      });
      if (claimed.count !== 1) throw new Error('Este convite já foi utilizado ou expirou.');
      await tx.driver.update({
        where: { id: invite.driverId },
        data: { passwordHash }
      });
    });
    const user = { id: invite.driver.id, role: 'DRIVER', companyId: invite.companyId };
    res.status(201).json({
      token: issueToken(user),
      user: {
        id: invite.driver.id,
        name: invite.driver.name,
        email: invite.driver.email,
        role: user.role,
        company: invite.driver.company
      }
    });
  } catch (error) {
    if (error.message.includes('convite')) return res.status(409).json({ error: error.message });
    console.error('Falha ao ativar conta de motorista:', error);
    res.status(500).json({ error: 'Não foi possível ativar a conta agora.' });
  }
});

app.post('/students/:studentId/tracking-grants', authenticate, requireOwner, async (req, res) => {
  try {
    const student = await prisma.student.findUnique({ where: { id: req.params.studentId } });
    if (!student || !(await companyForUser(req.user, student.companyId))) {
      return res.status(404).json({ error: 'Aluno não encontrado.' });
    }
    if (req.body.consentConfirmed !== true) {
      return res.status(400).json({ error: 'Confirme que o responsável autorizou o compartilhamento temporário da localização.' });
    }
    const code = createAccessCode();
    const expiresAt = new Date(Date.now() + 12 * 60 * 60 * 1000);
    await prisma.$transaction([
      prisma.studentTrackingGrant.updateMany({
        where: { studentId: student.id, revokedAt: null },
        data: { revokedAt: new Date() }
      }),
      prisma.studentTrackingGrant.create({
        data: {
          studentId: student.id,
          codeHash: hashAccessCode(code),
          consentAt: new Date(),
          expiresAt
        }
      })
    ]);
    res.status(201).json({ trackingCode: code, expiresAt });
  } catch (error) {
    console.error('Falha ao criar acesso de acompanhamento familiar:', error);
    res.status(500).json({ error: 'Não foi possível criar o acesso de acompanhamento.' });
  }
});

app.delete('/students/:studentId/tracking-grants', authenticate, requireOwner, async (req, res) => {
  const student = await prisma.student.findUnique({ where: { id: req.params.studentId } });
  if (!student || !(await companyForUser(req.user, student.companyId))) {
    return res.status(404).json({ error: 'Aluno não encontrado.' });
  }
  await prisma.studentTrackingGrant.updateMany({
    where: { studentId: student.id, revokedAt: null },
    data: { revokedAt: new Date() }
  });
  res.status(204).end();
});

app.get('/public/student-tracking/:code', async (req, res) => {
  const grant = await prisma.studentTrackingGrant.findFirst({
    where: {
      codeHash: hashAccessCode(req.params.code),
      revokedAt: null,
      expiresAt: { gt: new Date() },
      student: { is: { active: true } }
    },
    include: { student: { select: { id: true, name: true } } }
  });
  if (!grant) return res.status(404).json({ error: 'Este acesso expirou ou foi revogado.' });
  const assignment = await prisma.studentRunAssignment.findFirst({
    where: {
      studentId: grant.studentId,
      serviceRun: { is: { status: 'ACTIVE' } }
    },
    include: {
      serviceRun: {
        include: {
          vehicle: { select: { plate: true, model: true, location: true } },
          route: { select: { name: true, startTime: true, endTime: true } },
          charterTrip: { select: { origin: true, destination: true } },
          attendances: {
            where: { studentId: grant.studentId },
            select: { direction: true, date: true }
          }
        }
      }
    },
    orderBy: { serviceRun: { createdAt: 'desc' } }
  });
  const run = assignment?.serviceRun;
  const location = run && locationIsFresh(run.vehicle.location)
    ? {
        latitude: run.vehicle.location.latitude,
        longitude: run.vehicle.location.longitude,
        updatedAt: run.vehicle.location.updatedAt
      }
    : null;
  res.set('Cache-Control', 'no-store');
  res.json({
    studentName: grant.student.name.trim().split(/\s+/)[0],
    status: run ? 'EM_ROTA' : 'AGUARDANDO',
    vehicle: run ? { plate: run.vehicle.plate, model: run.vehicle.model } : null,
    route: run?.route?.name ?? (run?.charterTrip
      ? `${run.charterTrip.origin} → ${run.charterTrip.destination}`
      : null),
    location,
    attendance: assignment?.serviceRun.attendances.map(item => ({
      direction: item.direction,
      date: item.date
    })) ?? [],
    expiresAt: grant.expiresAt
  });
});

app.get('/auth/me', authenticate, async (req, res) => {
  if (req.user.role === 'OWNER') {
    const owner = await prisma.owner.findUnique({
      where: { id: req.user.sub },
      include: { companies: { select: { id: true, name: true } } }
    });
    if (!owner) return res.status(401).json({ error: 'Conta não encontrada.' });
    return res.json({
      id: owner.id,
      name: owner.name,
      email: owner.email,
      role: 'OWNER',
      companies: owner.companies
    });
  }
  const driver = await prisma.driver.findUnique({
    where: { id: req.user.sub },
    include: { company: { select: { id: true, name: true } } }
  });
  if (!driver || !driver.active) return res.status(401).json({ error: 'Conta de motorista inativa.' });
  return res.json({
    id: driver.id,
    name: driver.name,
    email: driver.email,
    role: 'DRIVER',
    company: driver.company
  });
});

app.get('/owners/:ownerId/companies', authenticate, requireOwner, async (req, res) => {
  if (req.params.ownerId !== req.user.sub) {
    return res.status(403).json({ error: 'Acesso não autorizado.' });
  }
  const companies = await prisma.company.findMany({
    where: { ownerId: req.user.sub },
    include: { _count: { select: { vehicles: true, drivers: true, students: true } } }
  });
  res.json(companies);
});

app.post('/companies', authenticate, requireOwner, async (req, res) => {
  if (typeof req.body.name !== 'string' || !req.body.name.trim()) {
    return res.status(400).json({ error: 'Informe o nome da empresa.' });
  }
  try {
    const company = await prisma.company.create({
      data: {
        name: req.body.name.trim(),
        cnpj: typeof req.body.cnpj === 'string' && req.body.cnpj.trim()
          ? req.body.cnpj.trim()
          : null,
        ownerId: req.user.sub
      }
    });
    res.status(201).json(company);
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'CNPJ já cadastrado.' });
    console.error('Falha ao criar empresa:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar a empresa.' });
  }
});

app.get('/companies/:companyId/dashboard', authenticate, requireOwner, async (req, res) => {
  try {
    if (!(await companyForUser(req.user, req.params.companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const purpose = req.query.purpose;
    if (purpose && !['ESCOLAR', 'TURISMO', 'EVENTOS'].includes(purpose)) {
      return res.status(400).json({ error: 'Tipo de serviço inválido.' });
    }
    const dateFilter = {};
    if (req.query.from) {
      dateFilter.gte = new Date(req.query.from);
      if (Number.isNaN(dateFilter.gte.getTime())) {
        return res.status(400).json({ error: 'Data inicial inválida.' });
      }
    }
    if (req.query.to) {
      const to = new Date(req.query.to);
      if (Number.isNaN(to.getTime())) {
        return res.status(400).json({ error: 'Data final inválida.' });
      }
      to.setUTCDate(to.getUTCDate() + 1);
      dateFilter.lt = to;
    }
    if (dateFilter.gte && dateFilter.lt && dateFilter.gte >= dateFilter.lt) {
      return res.status(400).json({ error: 'O período informado é inválido.' });
    }
    const transactionWhere = {
      companyId: req.params.companyId,
      ...(Object.keys(dateFilter).length ? { date: dateFilter } : {}),
      ...(purpose ? { vehicle: { is: { purposes: { has: purpose } } } } : {})
    };
    const [vehicles, transactions, students, drivers, activeRuns, emergencies] = await Promise.all([
      prisma.vehicle.findMany({
        where: { companyId: req.params.companyId },
        include: {
          defaultDriver: { select: { id: true, name: true, status: true } },
          location: true
        }
      }),
      prisma.financialTransaction.findMany({
        where: transactionWhere,
        include: { vehicle: { select: { id: true, plate: true } } },
        orderBy: { date: 'desc' }
      }),
      prisma.student.count({ where: { companyId: req.params.companyId, active: true } }),
      prisma.driver.count({ where: { companyId: req.params.companyId, active: true } }),
      prisma.serviceRun.findMany({
        where: { companyId: req.params.companyId, status: 'ACTIVE' },
        include: {
          vehicle: { select: { id: true, plate: true, model: true } },
          driver: { select: { id: true, name: true } },
          route: { select: { id: true, name: true } },
          charterTrip: { select: { id: true, origin: true, destination: true } }
        }
      }),
      prisma.emergencyRequest.findMany({
        where: { companyId: req.params.companyId, status: 'OPEN' },
        include: {
          student: { select: { name: true, pickupAddr: true } },
          brokenVehicle: { select: { plate: true } },
          offers: { where: { status: 'PENDING' }, include: { vehicle: { select: { plate: true } } } }
        },
        orderBy: { createdAt: 'desc' }
      })
    ]);
    const fleetStatus = { PARADO: 0, RODANDO: 0, MANUTENCAO: 0, DANIFICADA: 0, total: vehicles.length };
    vehicles.forEach(vehicle => { fleetStatus[vehicle.status] += 1; });
    const totalRevenue = transactions.reduce((sum, item) =>
      item.type === 'RECEITA' ? sum + Number(item.amount) : sum, 0);
    const totalExpenses = transactions.reduce((sum, item) =>
      item.type === 'DESPESA' ? sum + Number(item.amount) : sum, 0);
    const reportVehicles = purpose
      ? vehicles.filter(vehicle => vehicle.purposes.includes(purpose))
      : vehicles;
    const vehicleFinancials = new Map(reportVehicles.map(vehicle => [
      vehicle.id,
      { vehicleId: vehicle.id, plate: vehicle.plate, model: vehicle.model, revenue: 0, expenses: 0, netProfit: 0 }
    ]));
    let unallocatedExpenses = 0;
    transactions.forEach(item => {
      if (!item.vehicleId) {
        if (item.type === 'DESPESA') unallocatedExpenses += Number(item.amount);
        return;
      }
      const financial = vehicleFinancials.get(item.vehicleId);
      if (!financial) return;
      if (item.type === 'RECEITA') financial.revenue += Number(item.amount);
      else financial.expenses += Number(item.amount);
      financial.netProfit = financial.revenue - financial.expenses;
    });
    const visibleVehicles = vehicles.map(vehicle => ({
      ...vehicle,
      location: locationIsFresh(vehicle.location) ? vehicle.location : null
    }));
    res.json({
      financial: { revenue: totalRevenue, expenses: totalExpenses, netProfit: totalRevenue - totalExpenses },
      financialByVehicle: [...vehicleFinancials.values()],
      unallocatedExpenses,
      fleetStatus,
      turnoverRatePercent: vehicles.length ? Number(((fleetStatus.RODANDO / vehicles.length) * 100).toFixed(1)) : 0,
      counts: { students, drivers },
      activeRuns,
      emergencies,
      vehicles: visibleVehicles
    });
  } catch (error) {
    console.error('Falha ao carregar painel:', error);
    res.status(500).json({ error: 'Não foi possível carregar o painel.' });
  }
});

app.get('/companies/:companyId/agenda', authenticate, requireOwner, async (req, res) => {
  try {
    if (!(await companyForUser(req.user, req.params.companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const from = req.query.from ? new Date(req.query.from) : new Date();
    const to = req.query.to ? new Date(req.query.to) : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime()) || to < from) {
      return res.status(400).json({ error: 'Período da agenda inválido.' });
    }
    const [trips, schoolRoutes] = await Promise.all([
      prisma.charterTrip.findMany({
      where: {
        companyId: req.params.companyId,
        status: { not: 'CANCELADO' },
        departureDate: { lte: to },
        returnDate: { gte: from }
      },
      include: {
        vehicle: { select: { id: true, plate: true, model: true } },
        driver: { select: { id: true, name: true, phone: true } }
      },
      orderBy: { departureDate: 'asc' }
      }),
      prisma.schoolRoute.findMany({
        where: { vehicle: { is: { companyId: req.params.companyId } } },
        include: {
          vehicle: {
            select: {
              id: true,
              plate: true,
              model: true,
              defaultDriver: { select: { id: true, name: true } }
            }
          }
        },
        orderBy: [{ startTime: 'asc' }, { name: 'asc' }]
      })
    ]);
    res.json({ trips, schoolRoutes });
  } catch (error) {
    console.error('Falha ao carregar agenda:', error);
    res.status(500).json({ error: 'Não foi possível carregar a agenda.' });
  }
});

app.get('/vehicles/:vehicleId/context', authenticate, async (req, res) => {
  try {
    const [vehicle, vehicleTotals] = await Promise.all([
      prisma.vehicle.findUnique({
      where: { id: req.params.vehicleId },
      include: {
        defaultDriver: {
          select: { id: true, name: true, cnhCategory: true, phone: true, email: true, status: true }
        },
        transactions: { orderBy: { date: 'desc' }, take: 20 },
        location: true
      }
      }),
      prisma.financialTransaction.groupBy({
        by: ['type'],
        where: { vehicleId: req.params.vehicleId },
        _sum: { amount: true }
      })
    ]);
    if (!vehicle || !(await accessibleVehicle(req.user, vehicle.id))) {
      return res.status(404).json({ error: 'Veículo não encontrado.' });
    }
    const vehicleRevenue = vehicleTotals
      .filter(item => item.type === 'RECEITA')
      .reduce((sum, item) => sum + Number(item._sum.amount || 0), 0);
    const vehicleExpenses = vehicleTotals
      .filter(item => item.type === 'DESPESA')
      .reduce((sum, item) => sum + Number(item._sum.amount || 0), 0);
    const profit = vehicleRevenue - vehicleExpenses;
    const modules = {};
    if (vehicle.purposes.includes('ESCOLAR')) {
      const [students, routes] = await Promise.all([
        prisma.student.findMany({
          where: { vehicleId: vehicle.id, active: true },
          include: { attendances: { orderBy: { date: 'desc' }, take: 30 } }
        }),
        prisma.schoolRoute.findMany({ where: { vehicleId: vehicle.id } })
      ]);
      modules.escolar = {
        studentCount: students.length,
        occupancyRate: `${students.length}/${vehicle.capacity}`,
        expectedMonthlyRevenue: students.reduce((sum, item) => sum + Number(item.monthlyFee || 0), 0),
        routes,
        students
      };
    }
    if (vehicle.purposes.some(purpose => ['TURISMO', 'EVENTOS'].includes(purpose))) {
      const trips = await prisma.charterTrip.findMany({
        where: { vehicleId: vehicle.id },
        include: { driver: true },
        orderBy: { departureDate: 'asc' }
      });
      modules.fretamento = {
        upcomingTripsCount: trips.filter(trip => trip.status === 'AGENDADO').length,
        trips
      };
    }
    res.json({
      vehicleInfo: {
        id: vehicle.id, companyId: vehicle.companyId, plate: vehicle.plate, model: vehicle.model, year: vehicle.year,
        capacity: vehicle.capacity, description: vehicle.description, status: vehicle.status,
        purposes: vehicle.purposes,
        defaultDriver: vehicle.defaultDriver,
        location: locationIsFresh(vehicle.location) ? vehicle.location : null
      },
      financialSummary: {
        revenue: vehicleRevenue,
        expenses: vehicleExpenses,
        netProfit: profit,
        recentTransactions: vehicle.transactions
      },
      modules
    });
  } catch (error) {
    console.error('Falha ao carregar veículo:', error);
    res.status(500).json({ error: 'Não foi possível carregar o veículo.' });
  }
});

app.get('/companies/:companyId/drivers', authenticate, requireOwner, async (req, res) => {
  if (!(await companyForUser(req.user, req.params.companyId))) {
    return res.status(404).json({ error: 'Empresa não encontrada.' });
  }
  const drivers = await prisma.driver.findMany({
    where: { companyId: req.params.companyId, active: true },
    select: {
      id: true,
      companyId: true,
      name: true,
      cnh: true,
      cnhCategory: true,
      phone: true,
      email: true,
      passwordHash: true,
      status: true,
      active: true,
      vehicles: { select: { id: true, plate: true, model: true } }
    },
    orderBy: { name: 'asc' }
  });
  res.json(drivers.map(({ passwordHash, ...driver }) => ({
    ...driver,
    invitationPending: !passwordHash
  })));
});

app.post('/drivers/:driverId/invitations', authenticate, requireOwner, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({
      where: { id: req.params.driverId },
      select: { id: true, companyId: true, active: true, passwordHash: true }
    });
    if (!driver || !(await companyForUser(req.user, driver.companyId))) {
      return res.status(404).json({ error: 'Motorista não encontrado.' });
    }
    if (!driver.active || driver.passwordHash) {
      return res.status(409).json({ error: 'A conta deste motorista não está aguardando ativação.' });
    }
    const code = createAccessCode();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
    await prisma.$transaction(async tx => {
      await tx.driverInvite.updateMany({
        where: { driverId: driver.id, acceptedAt: null, revokedAt: null },
        data: { revokedAt: new Date() }
      });
      await tx.driverInvite.create({
        data: {
          companyId: driver.companyId,
          driverId: driver.id,
          codeHash: hashAccessCode(code),
          expiresAt
        }
      });
    });
    res.status(201).json({ activationCode: code, expiresAt });
  } catch (error) {
    console.error('Falha ao renovar convite do motorista:', error);
    res.status(500).json({ error: 'Não foi possível renovar o convite agora.' });
  }
});

app.get('/companies/:companyId/vehicles', authenticate, requireOwner, async (req, res) => {
  if (!(await companyForUser(req.user, req.params.companyId))) {
    return res.status(404).json({ error: 'Empresa não encontrada.' });
  }
  const vehicles = await prisma.vehicle.findMany({
    where: { companyId: req.params.companyId },
    select: {
      id: true,
      plate: true,
      model: true,
      year: true,
      capacity: true,
      description: true,
      purposes: true,
      status: true,
      defaultDriver: { select: { id: true, name: true, email: true } },
      location: true
    },
    orderBy: { plate: 'asc' }
  });
  res.json(vehicles.map(vehicle => ({
    ...vehicle,
    location: locationIsFresh(vehicle.location) ? vehicle.location : null
  })));
});

app.post('/drivers', authenticate, requireOwner, async (req, res) => {
  try {
    const { companyId, name, cnh, cnhCategory, phone, email, password, vehicleId } = req.body;
    if (![companyId, name, cnh, phone, email, password].every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Preencha empresa, nome, CNH, telefone, e-mail e senha.' });
    }
    if (password.length < 8) return res.status(400).json({ error: 'A senha precisa ter pelo menos 8 caracteres.' });
    if (!(await companyForUser(req.user, companyId))) return res.status(404).json({ error: 'Empresa não encontrada.' });
    if (await prisma.owner.findUnique({ where: { email: email.trim().toLowerCase() }, select: { id: true } })) {
      return res.status(409).json({ error: 'E-mail já vinculado a uma conta de proprietário.' });
    }
    if (vehicleId) {
      const vehicle = await prisma.vehicle.findFirst({ where: { id: vehicleId, companyId } });
      if (!vehicle) return res.status(400).json({ error: 'Van inválida para esta empresa.' });
      if (vehicle.defaultDriverId) return res.status(409).json({ error: 'A van já possui motorista titular.' });
    }
    const driver = await prisma.driver.create({
      data: {
        companyId, name: name.trim(), cnh: cnh.trim(), cnhCategory: cnhCategory || 'D',
        phone: phone.trim(), email: email.trim().toLowerCase(),
        passwordHash: await bcrypt.hash(password, 12),
        ...(vehicleId ? { vehicles: { connect: [{ id: vehicleId }] } } : {})
      },
      select: { id: true, companyId: true, name: true, cnh: true, cnhCategory: true, phone: true, email: true, status: true }
    });
    if (vehicleId) {
      await prisma.vehicle.update({ where: { id: vehicleId }, data: { defaultDriverId: driver.id } });
    }
    res.status(201).json(driver);
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'E-mail já cadastrado.' });
    console.error('Falha ao criar motorista:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar o motorista.' });
  }
});

app.patch('/drivers/:id', authenticate, requireOwner, async (req, res) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.params.id } });
    if (!driver || !(await companyForUser(req.user, driver.companyId))) {
      return res.status(404).json({ error: 'Motorista não encontrado.' });
    }
    const data = {};
    for (const field of ['name', 'cnh', 'cnhCategory', 'phone']) {
      if (typeof req.body[field] === 'string' && req.body[field].trim()) data[field] = req.body[field].trim();
    }
    if (req.body.email) data.email = req.body.email.trim().toLowerCase();
    if (req.body.password) {
      if (req.body.password.length < 8) return res.status(400).json({ error: 'A senha precisa ter pelo menos 8 caracteres.' });
      data.passwordHash = await bcrypt.hash(req.body.password, 12);
    }
    if ('vehicleId' in req.body && req.body.vehicleId) {
      const targetVehicle = await prisma.vehicle.findFirst({
        where: { id: req.body.vehicleId, companyId: driver.companyId }
      });
      if (!targetVehicle) return res.status(400).json({ error: 'Van inválida para esta empresa.' });
      if (targetVehicle.defaultDriverId && targetVehicle.defaultDriverId !== driver.id) {
        return res.status(409).json({ error: 'A van já possui outro motorista titular.' });
      }
    }
    const updated = await prisma.$transaction(async tx => {
      const result = await tx.driver.update({
        where: { id: driver.id },
        data,
        select: { id: true, name: true, cnh: true, cnhCategory: true, phone: true, email: true, status: true }
      });
      if ('vehicleId' in req.body) {
        await tx.vehicle.updateMany({
          where: { defaultDriverId: driver.id },
          data: { defaultDriverId: null }
        });
        if (req.body.vehicleId) {
          await tx.vehicle.update({
            where: { id: req.body.vehicleId },
            data: { defaultDriverId: driver.id }
          });
        }
      }
      return result;
    });
    res.json(updated);
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'E-mail já cadastrado.' });
    console.error('Falha ao editar motorista:', error);
    res.status(400).json({ error: 'Não foi possível atualizar o motorista.' });
  }
});

app.delete('/drivers/:id', authenticate, requireOwner, async (req, res) => {
  const driver = await prisma.driver.findUnique({ where: { id: req.params.id } });
  if (!driver || !(await companyForUser(req.user, driver.companyId))) {
    return res.status(404).json({ error: 'Motorista não encontrado.' });
  }
  await prisma.$transaction([
    prisma.vehicle.updateMany({ where: { defaultDriverId: driver.id }, data: { defaultDriverId: null } }),
    prisma.driver.update({ where: { id: driver.id }, data: { active: false, status: 'AFASTADO' } })
  ]);
  res.status(204).end();
});

app.get('/companies/:companyId/students', authenticate, requireOwner, async (req, res) => {
  if (!(await companyForUser(req.user, req.params.companyId))) {
    return res.status(404).json({ error: 'Empresa não encontrada.' });
  }
  const students = await prisma.student.findMany({
    where: { companyId: req.params.companyId, active: true },
    include: { vehicle: { select: { id: true, plate: true, model: true } } },
    orderBy: { name: 'asc' }
  });
  res.json(students);
});

app.post('/students', authenticate, requireOwner, async (req, res) => {
  try {
    const { companyId, vehicleId, name, guardian, phone, pickupAddr, schoolName, shift } = req.body;
    if (![companyId, name, guardian, phone, pickupAddr, schoolName, shift].every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Preencha todos os dados obrigatórios do aluno.' });
    }
    if (!(await companyForUser(req.user, companyId))) return res.status(404).json({ error: 'Empresa não encontrada.' });
    if (vehicleId && !(await prisma.vehicle.findFirst({ where: { id: vehicleId, companyId, purposes: { has: 'ESCOLAR' } } }))) {
      return res.status(400).json({ error: 'Van escolar inválida para esta empresa.' });
    }
    const student = await prisma.student.create({
      data: {
        companyId, vehicleId: vehicleId || null, name: name.trim(), guardian: guardian.trim(),
        phone: phone.trim(), pickupAddr: pickupAddr.trim(), schoolName: schoolName.trim(),
        pickupLatitude: optionalCoordinate(req.body.pickupLatitude, 'Latitude do endereço', -90, 90),
        pickupLongitude: optionalCoordinate(req.body.pickupLongitude, 'Longitude do endereço', -180, 180),
        shift, billingType: req.body.billingType || 'MENSAL',
        hasCellphone: req.body.hasCellphone !== false,
        monthlyFee: req.body.monthlyFee === '' || req.body.monthlyFee == null ? null : Number(req.body.monthlyFee),
        dueDay: req.body.dueDay === '' || req.body.dueDay == null ? null : Number(req.body.dueDay),
        pricePerTrip: req.body.pricePerTrip === '' || req.body.pricePerTrip == null ? null : Number(req.body.pricePerTrip)
      }
    });
    res.status(201).json(student);
  } catch (error) {
    console.error('Falha ao criar aluno:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar o aluno. Confira os dados informados.' });
  }
});

app.patch('/students/:id', authenticate, requireOwner, async (req, res) => {
  try {
    const student = await prisma.student.findUnique({ where: { id: req.params.id } });
    if (!student || !(await companyForUser(req.user, student.companyId))) {
      return res.status(404).json({ error: 'Aluno não encontrado.' });
    }
    if (req.body.vehicleId && !(await prisma.vehicle.findFirst({
      where: { id: req.body.vehicleId, companyId: student.companyId, purposes: { has: 'ESCOLAR' } }
    }))) return res.status(400).json({ error: 'Van escolar inválida para esta empresa.' });
    const data = {};
    for (const field of ['name', 'guardian', 'phone', 'pickupAddr', 'schoolName', 'shift', 'billingType']) {
      if (typeof req.body[field] === 'string' && req.body[field].trim()) data[field] = req.body[field].trim();
    }
    if ('vehicleId' in req.body) data.vehicleId = req.body.vehicleId || null;
    if ('pickupLatitude' in req.body) {
      data.pickupLatitude = optionalCoordinate(req.body.pickupLatitude, 'Latitude do endereço', -90, 90);
    }
    if ('pickupLongitude' in req.body) {
      data.pickupLongitude = optionalCoordinate(req.body.pickupLongitude, 'Longitude do endereço', -180, 180);
    }
    if (typeof req.body.hasCellphone === 'boolean') data.hasCellphone = req.body.hasCellphone;
    if ('monthlyFee' in req.body) data.monthlyFee = req.body.monthlyFee == null || req.body.monthlyFee === '' ? null : Number(req.body.monthlyFee);
    if ('dueDay' in req.body) data.dueDay = req.body.dueDay == null || req.body.dueDay === '' ? null : Number(req.body.dueDay);
    if ('pricePerTrip' in req.body) data.pricePerTrip = req.body.pricePerTrip == null || req.body.pricePerTrip === '' ? null : Number(req.body.pricePerTrip);
    res.json(await prisma.student.update({ where: { id: student.id }, data }));
  } catch (error) {
    console.error('Falha ao editar aluno:', error);
    res.status(400).json({ error: 'Não foi possível atualizar o aluno.' });
  }
});

app.delete('/students/:id', authenticate, requireOwner, async (req, res) => {
  const student = await prisma.student.findUnique({ where: { id: req.params.id } });
  if (!student || !(await companyForUser(req.user, student.companyId))) {
    return res.status(404).json({ error: 'Aluno não encontrado.' });
  }
  await prisma.student.update({ where: { id: student.id }, data: { active: false, vehicleId: null } });
  res.status(204).end();
});

app.post('/students/:id/buy-credits', authenticate, requireOwner, async (req, res) => {
  try {
    const quantity = Number(req.body.quantity);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 500) {
      return res.status(400).json({ error: 'Informe uma quantidade válida de viagens.' });
    }
    const student = await prisma.student.findUnique({ where: { id: req.params.id } });
    if (!student || !(await companyForUser(req.user, student.companyId))) {
      return res.status(404).json({ error: 'Aluno não encontrado.' });
    }
    if (student.billingType !== 'POR_VIAGEM') {
      return res.status(400).json({ error: 'O aluno não utiliza cobrança por viagem.' });
    }
    const unitPrice = Number(student.pricePerTrip);
    if (!Number.isFinite(unitPrice) || unitPrice <= 0) {
      return res.status(409).json({ error: 'Cadastre um preço por viagem antes de adicionar créditos.' });
    }
    const [updatedStudent] = await prisma.$transaction([
      prisma.student.update({
        where: { id: student.id },
        data: { tripCredits: { increment: quantity } }
      }),
      prisma.financialTransaction.create({
        data: {
          companyId: student.companyId,
          vehicleId: student.vehicleId,
          type: 'RECEITA',
          category: 'PACOTE_VIAGENS_ESCOLAR',
          amount: unitPrice * quantity,
          description: `Compra de ${quantity} viagens - Aluno(a): ${student.name}`
        }
      })
    ]);
    res.json({
      message: `${quantity} viagens adicionadas.`,
      newBalance: updatedStudent.tripCredits,
      revenueGenerated: unitPrice * quantity
    });
  } catch (error) {
    console.error('Falha ao adicionar créditos:', error);
    res.status(400).json({ error: 'Não foi possível adicionar os créditos.' });
  }
});

app.post('/vehicles', authenticate, requireOwner, async (req, res) => {
  try {
    const { companyId, plate, model, capacity, purposes, defaultDriverId } = req.body;
    if (!(await companyForUser(req.user, companyId))) return res.status(404).json({ error: 'Empresa não encontrada.' });
    if (!plate || !model || !Array.isArray(purposes) || !purposes.length) {
      return res.status(400).json({ error: 'Informe placa, modelo e finalidade da van.' });
    }
    if (defaultDriverId && !(await prisma.driver.findFirst({ where: { id: defaultDriverId, companyId, active: true } }))) {
      return res.status(400).json({ error: 'Motorista inválido para esta empresa.' });
    }
    const vehicle = await prisma.vehicle.create({
      data: {
        companyId, plate: String(plate).trim().toUpperCase(), model: String(model).trim(),
        year: req.body.year ? Number(req.body.year) : null,
        capacity: finiteNumber(capacity, 'Capacidade', 1, 100),
        description: req.body.description || null,
        purposes,
        defaultDriverId: defaultDriverId || null
      }
    });
    res.status(201).json(vehicle);
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'A placa já está cadastrada.' });
    console.error('Falha ao criar veículo:', error);
    res.status(400).json({ error: error.message || 'Não foi possível cadastrar a van.' });
  }
});

app.patch('/vehicles/:id/status', authenticate, async (req, res) => {
  const vehicle = await accessibleVehicle(req.user, req.params.id);
  if (!vehicle) return res.status(404).json({ error: 'Veículo não encontrado.' });
  if (req.user.role !== 'OWNER' && !['DANIFICADA'].includes(req.body.status)) {
    return res.status(403).json({ error: 'Motoristas só podem comunicar que a van está danificada.' });
  }
  const allowed = ['PARADO', 'RODANDO', 'MANUTENCAO', 'DANIFICADA'];
  if (!allowed.includes(req.body.status)) return res.status(400).json({ error: 'Status inválido.' });
  res.json(await prisma.vehicle.update({ where: { id: vehicle.id }, data: { status: req.body.status } }));
});

app.post('/driver/vehicles/:vehicleId/inspections', authenticate, requireActiveDriver, async (req, res) => {
  try {
    const driverId = req.user.sub;
    const vehicle = await prisma.vehicle.findFirst({
      where: { id: req.params.vehicleId, companyId: req.driver.companyId },
      select: { id: true, defaultDriverId: true }
    });
    if (!vehicle) return res.status(404).json({ error: 'Veículo não encontrado.' });
    if (req.body.charterTripId) {
      const trip = await prisma.charterTrip.findFirst({
        where: {
          id: req.body.charterTripId,
          companyId: req.driver.companyId,
          vehicleId: vehicle.id,
          driverId,
          status: 'AGENDADO'
        },
        select: { id: true }
      });
      if (!trip) return res.status(403).json({ error: 'Serviço não escalado para este motorista.' });
    } else if (req.body.offerId) {
      const offer = await prisma.emergencyOffer.findFirst({
        where: {
          id: req.body.offerId,
          vehicleId: vehicle.id,
          status: 'PENDING',
          request: { is: { status: 'OPEN' } }
        },
        select: { id: true }
      });
      if (!offer || vehicle.defaultDriverId !== driverId) {
        return res.status(403).json({ error: 'Esta van não está disponível para sua inspeção.' });
      }
    } else if (vehicle.defaultDriverId !== driverId) {
      return res.status(403).json({ error: 'Esta van não está atribuída a você.' });
    }

    const checks = ['tiresOk', 'lightsOk', 'brakesOk', 'documentsOk', 'cleanlinessOk'];
    if (!checks.every(field => typeof req.body[field] === 'boolean')) {
      return res.status(400).json({ error: 'Responda todos os itens da inspeção.' });
    }
    const blocked = checks.some(field => req.body[field] === false);
    const inspection = await prisma.vehicleInspection.create({
      data: {
        vehicleId: vehicle.id,
        driverId,
        tiresOk: req.body.tiresOk,
        lightsOk: req.body.lightsOk,
        brakesOk: req.body.brakesOk,
        documentsOk: req.body.documentsOk,
        cleanlinessOk: req.body.cleanlinessOk,
        notes: typeof req.body.notes === 'string' ? req.body.notes.trim().slice(0, 500) || null : null,
        blocked
      }
    });
    if (blocked) {
      return res.status(409).json({
        error: 'Inspeção registrou item de segurança reprovado. Não inicie o serviço e avise a empresa.',
        inspection
      });
    }
    res.status(201).json(inspection);
  } catch (error) {
    console.error('Falha ao registrar inspeção pré-viagem:', error);
    res.status(400).json({ error: 'Não foi possível registrar a inspeção.' });
  }
});

app.get('/vehicles/:vehicleId/operations', authenticate, async (req, res) => {
  const vehicle = await accessibleVehicle(req.user, req.params.vehicleId);
  if (!vehicle) return res.status(404).json({ error: 'Veículo não encontrado.' });
  const now = new Date();
  const [documents, inspections, locations, alerts] = await Promise.all([
    prisma.vehicleDocument.findMany({
      where: { vehicleId: vehicle.id },
      orderBy: { expiresAt: 'asc' }
    }),
    prisma.vehicleInspection.findMany({
      where: { vehicleId: vehicle.id },
      orderBy: { createdAt: 'desc' },
      take: 30,
      include: { driver: { select: { id: true, name: true } } }
    }),
    prisma.vehicleLocationSample.findMany({
      where: {
        vehicleId: vehicle.id,
        createdAt: { gte: new Date(now.getTime() - 24 * 60 * 60 * 1000) }
      },
      orderBy: { createdAt: 'desc' },
      take: 3000
    }),
    prisma.vehicleAlert.findMany({
      where: { vehicleId: vehicle.id, resolvedAt: null },
      orderBy: { createdAt: 'desc' },
      take: 50
    })
  ]);
  res.json({
    documents: documents.map(document => ({
      ...document,
      expiryStatus: document.expiresAt < now
        ? 'VENCIDO'
        : document.expiresAt.getTime() - now.getTime() <= 30 * 24 * 60 * 60 * 1000
          ? 'VENCE_EM_BREVE'
          : 'VALIDO'
    })),
    inspections,
    locationSamples: locations,
    alerts
  });
});

app.post('/vehicles/:vehicleId/documents', authenticate, requireOwner, async (req, res) => {
  try {
    const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.vehicleId } });
    if (!vehicle || !(await companyForUser(req.user, vehicle.companyId))) {
      return res.status(404).json({ error: 'Veículo não encontrado.' });
    }
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    const category = typeof req.body.category === 'string' ? req.body.category.trim() : '';
    const expiresAt = new Date(req.body.expiresAt);
    if (!name || !category || Number.isNaN(expiresAt.getTime())) {
      return res.status(400).json({ error: 'Informe nome, categoria e validade do documento.' });
    }
    const document = await prisma.vehicleDocument.create({
      data: {
        vehicleId: vehicle.id,
        name: name.slice(0, 120),
        category: category.slice(0, 80),
        expiresAt,
        notes: typeof req.body.notes === 'string' ? req.body.notes.trim().slice(0, 500) || null : null
      }
    });
    res.status(201).json(document);
  } catch (error) {
    console.error('Falha ao cadastrar documento da van:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar o documento.' });
  }
});

app.delete('/vehicles/:vehicleId/documents/:documentId', authenticate, requireOwner, async (req, res) => {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.vehicleId } });
  if (!vehicle || !(await companyForUser(req.user, vehicle.companyId))) {
    return res.status(404).json({ error: 'Veículo não encontrado.' });
  }
  const deleted = await prisma.vehicleDocument.deleteMany({
    where: { id: req.params.documentId, vehicleId: vehicle.id }
  });
  if (!deleted.count) return res.status(404).json({ error: 'Documento não encontrado.' });
  res.status(204).end();
});

app.post('/vehicles/:vehicleId/alerts/:alertId/acknowledge', authenticate, requireOwner, async (req, res) => {
  const vehicle = await prisma.vehicle.findUnique({ where: { id: req.params.vehicleId } });
  if (!vehicle || !(await companyForUser(req.user, vehicle.companyId))) {
    return res.status(404).json({ error: 'Veículo não encontrado.' });
  }
  const result = await prisma.vehicleAlert.updateMany({
    where: { id: req.params.alertId, vehicleId: vehicle.id, acknowledgedAt: null },
    data: { acknowledgedAt: new Date() }
  });
  if (!result.count) return res.status(404).json({ error: 'Alerta não encontrado.' });
  res.status(204).end();
});

app.get('/companies/:companyId/operational-alerts', authenticate, requireOwner, async (req, res) => {
  if (!(await companyForUser(req.user, req.params.companyId))) {
    return res.status(404).json({ error: 'Empresa não encontrada.' });
  }
  const today = new Date();
  const soon = new Date(today.getTime() + 30 * 24 * 60 * 60 * 1000);
  const [alerts, documents] = await Promise.all([
    prisma.vehicleAlert.findMany({
      where: { companyId: req.params.companyId, acknowledgedAt: null, resolvedAt: null },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { vehicle: { select: { id: true, plate: true, model: true } } }
    }),
    prisma.vehicleDocument.findMany({
      where: { vehicle: { companyId: req.params.companyId }, expiresAt: { lte: soon } },
      orderBy: { expiresAt: 'asc' },
      include: { vehicle: { select: { id: true, plate: true, model: true } } }
    })
  ]);
  res.json({
    alerts,
    expiringDocuments: documents.map(document => ({
      ...document,
      expiryStatus: document.expiresAt < today ? 'VENCIDO' : 'VENCE_EM_BREVE'
    }))
  });
});

app.post('/school-routes', authenticate, requireOwner, async (req, res) => {
  try {
    const vehicle = await prisma.vehicle.findUnique({ where: { id: req.body.vehicleId } });
    if (!vehicle || !(await companyForUser(req.user, vehicle.companyId)) || !vehicle.purposes.includes('ESCOLAR')) {
      return res.status(400).json({ error: 'Van escolar inválida.' });
    }
    const { name, shift, startTime, endTime } = req.body;
    if (![name, shift, startTime, endTime].every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Preencha nome, turno e horários da rota.' });
    }
    const daysOfWeek = req.body.daysOfWeek ?? [1, 2, 3, 4, 5];
    if (!Array.isArray(daysOfWeek) || !daysOfWeek.length ||
        daysOfWeek.some(day => !Number.isInteger(day) || day < 0 || day > 6)) {
      return res.status(400).json({ error: 'Selecione pelo menos um dia válido da semana.' });
    }
    res.status(201).json(await prisma.schoolRoute.create({
      data: {
        vehicleId: vehicle.id, name: name.trim(), shift, startTime, endTime,
        daysOfWeek: [...new Set(daysOfWeek)],
        schoolLatitude: optionalCoordinate(req.body.schoolLatitude, 'Latitude da escola', -90, 90),
        schoolLongitude: optionalCoordinate(req.body.schoolLongitude, 'Longitude da escola', -180, 180),
        stopsOrder: req.body.stopsOrder || []
      }
    }));
  } catch (error) {
    console.error('Falha ao criar rota:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar a rota.' });
  }
});

app.patch('/school-routes/:routeId', authenticate, requireOwner, async (req, res) => {
  try {
    const route = await prisma.schoolRoute.findUnique({
      where: { id: req.params.routeId },
      include: { vehicle: true }
    });
    if (!route || !(await companyForUser(req.user, route.vehicle.companyId))) {
      return res.status(404).json({ error: 'Rota não encontrada.' });
    }
    const data = {};
    for (const field of ['name', 'shift', 'startTime', 'endTime']) {
      if (typeof req.body[field] === 'string' && req.body[field].trim()) data[field] = req.body[field].trim();
    }
    if (Array.isArray(req.body.stopsOrder)) data.stopsOrder = req.body.stopsOrder;
    if ('daysOfWeek' in req.body) {
      if (!Array.isArray(req.body.daysOfWeek) || !req.body.daysOfWeek.length ||
          req.body.daysOfWeek.some(day => !Number.isInteger(day) || day < 0 || day > 6)) {
        return res.status(400).json({ error: 'Selecione pelo menos um dia válido da semana.' });
      }
      data.daysOfWeek = [...new Set(req.body.daysOfWeek)];
    }
    if ('schoolLatitude' in req.body) {
      data.schoolLatitude = optionalCoordinate(req.body.schoolLatitude, 'Latitude da escola', -90, 90);
    }
    if ('schoolLongitude' in req.body) {
      data.schoolLongitude = optionalCoordinate(req.body.schoolLongitude, 'Longitude da escola', -180, 180);
    }
    res.json(await prisma.schoolRoute.update({ where: { id: route.id }, data }));
  } catch (error) {
    console.error('Falha ao atualizar rota escolar:', error);
    res.status(400).json({ error: 'Não foi possível atualizar a rota.' });
  }
});

app.delete('/school-routes/:routeId', authenticate, requireOwner, async (req, res) => {
  const route = await prisma.schoolRoute.findUnique({
    where: { id: req.params.routeId },
    include: { vehicle: true }
  });
  if (!route || !(await companyForUser(req.user, route.vehicle.companyId))) {
    return res.status(404).json({ error: 'Rota não encontrada.' });
  }
  if (await prisma.serviceRun.findFirst({ where: { routeId: route.id, status: 'ACTIVE' } })) {
    return res.status(409).json({ error: 'Não é possível excluir uma rota em andamento.' });
  }
  await prisma.schoolRoute.delete({ where: { id: route.id } });
  res.status(204).end();
});

app.get('/driver/me', authenticate, requireActiveDriver, async (req, res) => {
  if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
  const driver = await prisma.driver.findUnique({
    where: { id: req.user.sub },
    select: {
      id: true,
      companyId: true,
      name: true,
      cnh: true,
      cnhCategory: true,
      phone: true,
      email: true,
      active: true,
      status: true,
      vehicles: {
        include: {
          schoolRoutes: true,
          location: true
        }
      }
    }
  });
  if (!driver || !driver.active) return res.status(401).json({ error: 'Conta de motorista inativa.' });
  const scheduledServices = await prisma.charterTrip.findMany({
    where: {
      companyId: driver.companyId,
      driverId: driver.id,
      status: 'AGENDADO',
      returnDate: { gte: new Date() }
    },
    select: {
      id: true,
      type: true,
      clientName: true,
      clientPhone: true,
      origin: true,
      destination: true,
      departureDate: true,
      returnDate: true,
      agreedValue: true,
      notes: true,
      status: true,
      passengers: {
        orderBy: { name: 'asc' }
      },
      vehicle: { select: { id: true, plate: true, model: true, status: true } }
    },
    orderBy: { departureDate: 'asc' }
  });
  const activeRuns = await prisma.serviceRun.findMany({
    where: { driverId: driver.id, status: 'ACTIVE' },
    include: {
      vehicle: { select: { id: true, plate: true, model: true, location: true } },
      route: true,
      charterTrip: {
        select: {
          id: true,
          type: true,
          clientName: true,
          clientPhone: true,
          origin: true,
          destination: true,
          departureDate: true,
          returnDate: true,
          agreedValue: true,
          notes: true,
          status: true,
          passengers: {
            orderBy: { name: 'asc' }
          }
        }
      },
      assignments: {
        where: { assignedVehicleId: { in: driver.vehicles.map(vehicle => vehicle.id) } },
        select: {
          id: true,
          serviceRunId: true,
          studentId: true,
          assignedVehicleId: true,
          temporary: true,
          student: {
            select: {
              id: true,
              name: true,
              pickupAddr: true,
              pickupLatitude: true,
              pickupLongitude: true,
              schoolName: true,
              shift: true,
              hasCellphone: true,
              attendances: {
                where: { serviceRunId: { not: null } },
                select: { serviceRunId: true, direction: true },
                orderBy: { date: 'desc' },
                take: 4
              }
            }
          }
        }
      },
      emergencies: { where: { status: 'OPEN' }, include: { student: { select: { id: true, name: true } } } }
    }
  });
  const offers = await prisma.emergencyOffer.findMany({
    where: { vehicle: { defaultDriverId: driver.id }, status: 'PENDING', request: { status: 'OPEN' } },
    include: {
      request: {
        include: {
          student: { select: { id: true, name: true, pickupAddr: true } },
          brokenVehicle: { select: { plate: true, model: true } },
          serviceRun: { include: { route: true } }
        }
      },
      vehicle: { select: { id: true, plate: true, model: true } }
    },
    orderBy: { distanceMeters: 'asc' }
  });
  const freshVehicles = driver.vehicles.map(vehicle => ({
    ...vehicle,
    location: locationIsFresh(vehicle.location) ? vehicle.location : null
  }));
  const freshRuns = activeRuns.map(run => ({
    ...run,
    vehicle: {
      ...run.vehicle,
      location: locationIsFresh(run.vehicle.location) ? run.vehicle.location : null
    }
  }));
  res.json({ driver, vehicles: freshVehicles, activeRuns: freshRuns, scheduledServices, offers });
});

app.post('/driver/runs/start', authenticate, requireActiveDriver, async (req, res) => {
  try {
    if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
    if (req.body.routeId && req.body.charterTripId) {
      return res.status(400).json({ error: 'Inicie apenas um serviço por vez.' });
    }
    const driver = await prisma.driver.findUnique({ where: { id: req.user.sub } });
    if (!driver || !driver.active) return res.status(401).json({ error: 'Conta de motorista inativa.' });
    const scheduledTrip = req.body.charterTripId
      ? await prisma.charterTrip.findFirst({
          where: {
            id: req.body.charterTripId,
            companyId: driver.companyId,
            driverId: driver.id,
            status: 'AGENDADO'
          }
        })
      : null;
    if (req.body.charterTripId && !scheduledTrip) {
      return res.status(403).json({ error: 'Este serviço não está escalado para você.' });
    }
    if (scheduledTrip && req.body.vehicleId && req.body.vehicleId !== scheduledTrip.vehicleId) {
      return res.status(403).json({ error: 'A van informada não corresponde ao serviço escalado.' });
    }
    const vehicle = await prisma.vehicle.findFirst({
      where: {
        id: scheduledTrip?.vehicleId || req.body.vehicleId || undefined,
        ...(scheduledTrip ? {} : { defaultDriverId: driver.id }),
        companyId: driver.companyId,
        status: { notIn: ['DANIFICADA', 'MANUTENCAO'] }
      }
    });
    if (!vehicle) return res.status(400).json({ error: 'Você não possui uma van disponível para iniciar.' });
    if (await prisma.serviceRun.findFirst({ where: { driverId: driver.id, status: 'ACTIVE' } })) {
      return res.status(409).json({ error: 'Você já possui uma rota em andamento.' });
    }
    const inspection = await prisma.vehicleInspection.findFirst({
      where: {
        vehicleId: vehicle.id,
        driverId: driver.id,
        serviceRunId: null,
        blocked: false,
        createdAt: { gte: new Date(Date.now() - 12 * 60 * 60 * 1000) }
      },
      orderBy: { createdAt: 'desc' },
      select: { id: true }
    });
    if (!inspection) {
      return res.status(409).json({ error: 'Registre uma inspeção pré-viagem aprovada antes de iniciar.' });
    }
    let routeId = null;
    let charterTripId = null;
    let purpose = vehicle.purposes[0];
    if (req.body.routeId) {
      const route = await prisma.schoolRoute.findFirst({ where: { id: req.body.routeId, vehicleId: vehicle.id } });
      if (!route) return res.status(400).json({ error: 'Rota não pertence à sua van.' });
      routeId = route.id;
      purpose = 'ESCOLAR';
    }
    if (req.body.charterTripId) {
      charterTripId = scheduledTrip.id;
      purpose = scheduledTrip.type;
    }
    const run = await prisma.$transaction(async tx => {
      if (scheduledTrip) {
        const claimedTrip = await tx.charterTrip.updateMany({
          where: {
            id: scheduledTrip.id,
            driverId: driver.id,
            status: 'AGENDADO'
          },
          data: { status: 'EM_ANDAMENTO' }
        });
        if (claimedTrip.count !== 1) {
          throw new Error('Este serviço já foi iniciado ou não está mais disponível.');
        }
      }
      const claimedVehicle = await tx.vehicle.updateMany({
        where: { id: vehicle.id, status: 'PARADO' },
        data: { status: 'RODANDO' }
      });
      if (claimedVehicle.count !== 1) {
        throw new Error('Esta van já possui um serviço em andamento ou não está disponível.');
      }
      const claimedDriver = await tx.driver.updateMany({
        where: { id: driver.id, active: true, status: 'DISPONIVEL' },
        data: { status: 'EM_VIAGEM' }
      });
      if (claimedDriver.count !== 1) {
        throw new Error('O motorista não está disponível para iniciar o serviço.');
      }
      const created = await tx.serviceRun.create({
        data: {
          companyId: driver.companyId, vehicleId: vehicle.id, driverId: driver.id,
          routeId, charterTripId, purpose, status: 'ACTIVE', startedAt: new Date()
        }
      });
      await tx.vehicleInspection.update({
        where: { id: inspection.id },
        data: { serviceRunId: created.id }
      });
      if (purpose === 'ESCOLAR') {
        const students = await tx.student.findMany({
          where: { companyId: driver.companyId, vehicleId: vehicle.id, active: true },
          select: { id: true }
        });
        if (students.length) {
          await tx.studentRunAssignment.createMany({
            data: students.map(student => ({
              serviceRunId: created.id, studentId: student.id, assignedVehicleId: vehicle.id
            }))
          });
        }
      }
      return created;
    });
    io.to(`company:${driver.companyId}`).emit('run:started', { runId: run.id, vehicleId: vehicle.id });
    res.status(201).json(run);
  } catch (error) {
    console.error('Falha ao iniciar rota:', error);
    const statusCode = [
      'serviço já',
      'em andamento',
      'não está disponível'
    ].some(message => error.message.includes(message)) ? 409 : 400;
    res.status(statusCode).json({ error: error.message || 'Não foi possível iniciar a rota.' });
  }
});

app.post('/driver/runs/:runId/attendance', authenticate, requireActiveDriver, async (req, res) => {
  try {
    if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
    const run = await prisma.serviceRun.findFirst({
      where: { id: req.params.runId, driverId: req.user.sub, status: 'ACTIVE' }
    });
    if (!run) return res.status(404).json({ error: 'Rota ativa não encontrada.' });
    if (!['IDA', 'VOLTA'].includes(req.body.direction)) {
      return res.status(400).json({ error: 'A chamada deve ser de ida ou de volta.' });
    }
    const assignment = await prisma.studentRunAssignment.findUnique({
      where: { serviceRunId_studentId: { serviceRunId: run.id, studentId: req.body.studentId } },
      include: { student: true }
    });
    if (!assignment || assignment.assignedVehicleId !== run.vehicleId || !assignment.student.active) {
      return res.status(403).json({ error: 'Aluno não faz parte desta viagem.' });
    }
    const creditsUsed = await prisma.$transaction(async tx => {
      const count = await consumeTripCredit(tx, assignment.student, 1);
      await tx.studentAttendance.create({
        data: {
          studentId: assignment.studentId, vehicleId: run.vehicleId, serviceRunId: run.id,
          direction: req.body.direction, method: 'MANUAL_MOTORISTA', creditsUsed: count
        }
      });
      return count;
    });
    const attendance = await prisma.studentAttendance.findFirst({
      where: { serviceRunId: run.id, studentId: assignment.studentId, direction: req.body.direction },
      orderBy: { date: 'desc' }
    });
    io.to(`company:${run.companyId}`).emit('attendance:updated', {
      runId: run.id, studentId: assignment.studentId, direction: req.body.direction
    });
    res.status(201).json({ attendance, creditsUsed });
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'Esta chamada já foi registrada nesta viagem.' });
    if (error.message.includes('créditos')) return res.status(409).json({ error: error.message });
    console.error('Falha ao registrar chamada:', error);
    res.status(400).json({ error: 'Não foi possível registrar a presença.' });
  }
});

app.post('/driver/runs/:runId/location', authenticate, requireActiveDriver, async (req, res) => {
  try {
    if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
    const run = await prisma.serviceRun.findFirst({
      where: { id: req.params.runId, driverId: req.user.sub, status: 'ACTIVE' }
    });
    if (!run) return res.status(404).json({ error: 'Rota ativa não encontrada.' });
    const location = await prisma.vehicleLocation.upsert({
      where: { vehicleId: run.vehicleId },
      create: {
        vehicleId: run.vehicleId,
        latitude: finiteNumber(req.body.latitude, 'Latitude', -90, 90),
        longitude: finiteNumber(req.body.longitude, 'Longitude', -180, 180),
        accuracy: req.body.accuracy == null ? null : finiteNumber(req.body.accuracy, 'Precisão', 0, 10000),
        heading: req.body.heading == null ? null : finiteNumber(req.body.heading, 'Direção', 0, 360),
        speed: req.body.speed == null ? null : finiteNumber(req.body.speed, 'Velocidade', 0, 200)
      },
      update: {
        latitude: finiteNumber(req.body.latitude, 'Latitude', -90, 90),
        longitude: finiteNumber(req.body.longitude, 'Longitude', -180, 180),
        accuracy: req.body.accuracy == null ? null : finiteNumber(req.body.accuracy, 'Precisão', 0, 10000),
        heading: req.body.heading == null ? null : finiteNumber(req.body.heading, 'Direção', 0, 360),
        speed: req.body.speed == null ? null : finiteNumber(req.body.speed, 'Velocidade', 0, 200),
        updatedAt: new Date()
      }
    });
    const lastSample = await prisma.vehicleLocationSample.findFirst({
      where: { serviceRunId: run.id },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true }
    });
    if (!lastSample || Date.now() - lastSample.createdAt.getTime() >= 30_000) {
      await prisma.vehicleLocationSample.create({
        data: {
          vehicleId: run.vehicleId,
          serviceRunId: run.id,
          latitude: location.latitude,
          longitude: location.longitude,
          heading: location.heading,
          speed: location.speed
        }
      });
    }
    await prisma.vehicleAlert.updateMany({
      where: { serviceRunId: run.id, kind: 'GPS_SEM_SINAL', resolvedAt: null },
      data: { resolvedAt: new Date() }
    });
    io.to(`company:${run.companyId}`).emit('location:update', {
      vehicleId: run.vehicleId,
      runId: run.id,
      latitude: location.latitude,
      longitude: location.longitude,
      heading: location.heading,
      updatedAt: location.updatedAt
    });
    res.json(location);
  } catch (error) {
    console.error('Falha ao atualizar localização:', error);
    res.status(400).json({ error: error.message || 'Não foi possível atualizar a localização.' });
  }
});

app.post('/driver/runs/:runId/emergencies', authenticate, requireActiveDriver, async (req, res) => {
  try {
    if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
    const run = await prisma.serviceRun.findFirst({
      where: { id: req.params.runId, driverId: req.user.sub, status: 'ACTIVE' },
      include: { vehicle: { include: { location: true } } }
    });
    if (!run) return res.status(404).json({ error: 'Rota ativa não encontrada.' });
    const assignment = await prisma.studentRunAssignment.findUnique({
      where: { serviceRunId_studentId: { serviceRunId: run.id, studentId: req.body.studentId } },
      include: { student: true }
    });
    if (!assignment || assignment.assignedVehicleId !== run.vehicleId) {
      return res.status(400).json({ error: 'Selecione um aluno que ainda esteja nesta van.' });
    }
    if (!run.vehicle.location || Date.now() - run.vehicle.location.updatedAt.getTime() > 5 * 60 * 1000) {
      return res.status(409).json({ error: 'Ative a localização da van antes de solicitar apoio.' });
    }
    const pending = await prisma.emergencyRequest.findFirst({
      where: { serviceRunId: run.id, studentId: assignment.studentId, status: 'OPEN' }
    });
    if (pending) return res.status(409).json({ error: 'Já existe uma solicitação aberta para este aluno.' });
    const request = await prisma.emergencyRequest.create({
      data: {
        companyId: run.companyId, serviceRunId: run.id, brokenVehicleId: run.vehicleId,
        studentId: assignment.studentId,
        description: typeof req.body.description === 'string' && req.body.description.trim()
          ? req.body.description.trim().slice(0, 500)
          : 'Van indisponível durante a rota.'
      },
      include: {
        student: { select: { id: true, name: true, pickupAddr: true } },
        brokenVehicle: { select: { id: true, plate: true } }
      }
    });
    const offer = await issueNextEmergencyOffer(request);
    if (!offer) {
      await prisma.emergencyRequest.update({ where: { id: request.id }, data: { status: 'CANCELLED' } });
      return res.status(409).json({ error: 'Nenhuma van disponível com localização recente foi encontrada.' });
    }
    await prisma.vehicle.update({
      where: { id: run.vehicleId },
      data: { status: 'DANIFICADA' }
    });
    res.status(201).json({ request, offer });
  } catch (error) {
    console.error('Falha ao solicitar apoio:', error);
    res.status(400).json({ error: 'Não foi possível solicitar uma van substituta.' });
  }
});

app.post('/driver/emergency-offers/:offerId/respond', authenticate, requireActiveDriver, async (req, res) => {
  try {
    if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
    if (!['ACCEPTED', 'DECLINED'].includes(req.body.response)) {
      return res.status(400).json({ error: 'Resposta inválida.' });
    }
    const offer = await prisma.emergencyOffer.findFirst({
      where: {
        id: req.params.offerId, vehicle: { defaultDriverId: req.user.sub },
        status: 'PENDING', request: { status: 'OPEN' }
      },
      include: { request: { include: { serviceRun: true, student: true } }, vehicle: true }
    });
    if (!offer) return res.status(404).json({ error: 'Esta oferta não está mais disponível.' });
    if (req.body.response === 'DECLINED') {
      const declined = await prisma.emergencyOffer.updateMany({
        where: {
          id: offer.id,
          status: 'PENDING',
          request: { is: { status: 'OPEN' } }
        },
        data: { status: 'DECLINED', respondedAt: new Date() }
      });
      if (declined.count !== 1) {
        return res.status(409).json({ error: 'Esta oferta já foi respondida.' });
      }
      const replacement = await issueNextEmergencyOffer(
        offer.request,
        (await prisma.emergencyOffer.findMany({ where: { requestId: offer.requestId }, select: { vehicleId: true } }))
          .map(item => item.vehicleId)
      );
      if (!replacement) {
        const cancelled = await prisma.emergencyRequest.updateMany({
          where: { id: offer.requestId, status: 'OPEN' },
          data: { status: 'CANCELLED' }
        });
        if (cancelled.count === 1) {
          io.to(`company:${offer.request.companyId}`).emit('emergency:unassigned', { requestId: offer.requestId });
        }
      }
      return res.json({ status: 'DECLINED', nextOffer: replacement });
    }

    const inspection = await prisma.vehicleInspection.findFirst({
      where: {
        vehicleId: offer.vehicleId,
        driverId: req.user.sub,
        serviceRunId: null,
        blocked: false,
        createdAt: { gte: new Date(Date.now() - 12 * 60 * 60 * 1000) }
      },
      orderBy: { createdAt: 'desc' },
      select: { id: true }
    });
    if (!inspection) {
      return res.status(409).json({ error: 'Registre uma inspeção aprovada da van substituta antes de aceitar.' });
    }

    const run = await prisma.$transaction(async tx => {
      const current = await tx.emergencyOffer.findUnique({
        where: { id: offer.id },
        include: { request: true, vehicle: true }
      });
      if (!current || current.status !== 'PENDING' || current.request.status !== 'OPEN') {
        throw new Error('Esta oferta já foi respondida.');
      }
      if (current.vehicle.status !== 'PARADO') throw new Error('A van não está mais disponível.');
      if (await tx.serviceRun.findFirst({ where: { driverId: req.user.sub, status: 'ACTIVE' } })) {
        throw new Error('Finalize sua rota atual antes de aceitar a substituição.');
      }
      const claimedRequest = await tx.emergencyRequest.updateMany({
        where: { id: current.requestId, status: 'OPEN' },
        data: { status: 'ACCEPTED' }
      });
      if (claimedRequest.count !== 1) throw new Error('Esta oferta já foi respondida.');
      const claimedVehicle = await tx.vehicle.updateMany({
        where: { id: current.vehicleId, status: 'PARADO' },
        data: { status: 'RODANDO' }
      });
      if (claimedVehicle.count !== 1) throw new Error('A van não está mais disponível.');
      const claimedDriver = await tx.driver.updateMany({
        where: { id: req.user.sub, active: true, status: 'DISPONIVEL' },
        data: { status: 'EM_VIAGEM' }
      });
      if (claimedDriver.count !== 1) {
        throw new Error('O motorista não está mais disponível.');
      }
      const claimedOffer = await tx.emergencyOffer.updateMany({
        where: { id: current.id, status: 'PENDING' },
        data: { status: 'ACCEPTED', respondedAt: new Date() }
      });
      if (claimedOffer.count !== 1) throw new Error('Esta oferta já foi respondida.');
      const newRun = await tx.serviceRun.create({
        data: {
          companyId: current.request.companyId,
          vehicleId: current.vehicleId,
          driverId: req.user.sub,
          routeId: offer.request.serviceRun.routeId,
          purpose: offer.request.serviceRun.purpose,
          status: 'ACTIVE',
          startedAt: new Date()
        }
      });
      await tx.vehicleInspection.update({
        where: { id: inspection.id },
        data: { serviceRunId: newRun.id }
      });
      await tx.studentRunAssignment.create({
        data: {
          serviceRunId: newRun.id,
          studentId: current.request.studentId,
          assignedVehicleId: current.vehicleId,
          temporary: true
        }
      });
      await tx.emergencyRequest.update({
        where: { id: current.requestId },
        data: { replacementRunId: newRun.id }
      });
      await tx.emergencyOffer.updateMany({
        where: { requestId: current.requestId, status: 'PENDING', id: { not: current.id } },
        data: { status: 'EXPIRED', respondedAt: new Date() }
      });
      return newRun;
    });
    io.to(`company:${offer.request.companyId}`).emit('emergency:accepted', {
      requestId: offer.requestId, replacementRunId: run.id, vehicleId: offer.vehicleId
    });
    io.to(`driver:${offer.request.serviceRun.driverId}`).emit('emergency:assigned', {
      requestId: offer.requestId, studentId: offer.request.studentId
    });
    res.json({ status: 'ACCEPTED', runId: run.id });
  } catch (error) {
    if (error.message.includes('oferta') || error.message.includes('van não está') ||
        error.message.includes('não está mais disponível') || error.message.includes('Finalize')) {
      return res.status(409).json({ error: error.message });
    }
    console.error('Falha ao responder oferta:', error);
    res.status(400).json({ error: 'Não foi possível responder à solicitação.' });
  }
});

app.post('/driver/runs/:runId/end', authenticate, requireActiveDriver, async (req, res) => {
  if (req.user.role !== 'DRIVER') return res.status(403).json({ error: 'Área exclusiva do motorista.' });
  const run = await prisma.serviceRun.findFirst({
    where: { id: req.params.runId, driverId: req.user.sub, status: 'ACTIVE' }
  });
  if (!run) return res.status(404).json({ error: 'Rota ativa não encontrada.' });
  const unresolved = await prisma.emergencyRequest.count({
    where: { serviceRunId: run.id, status: 'OPEN' }
  });
  if (unresolved) return res.status(409).json({ error: 'Resolva as solicitações de apoio antes de encerrar a rota.' });
  try {
    await prisma.$transaction(async tx => {
      const completedRun = await tx.serviceRun.updateMany({
        where: { id: run.id, status: 'ACTIVE' },
        data: { status: 'COMPLETED', endedAt: new Date() }
      });
      if (completedRun.count !== 1) throw new Error('A rota já foi encerrada.');
      if (run.charterTripId) {
        const trip = await tx.charterTrip.findUnique({
          where: { id: run.charterTripId }
        });
        if (trip?.status === 'EM_ANDAMENTO') {
          const completedTrip = await tx.charterTrip.updateMany({
            where: { id: trip.id, status: 'EM_ANDAMENTO' },
            data: { status: 'CONCLUIDO' }
          });
          if (completedTrip.count === 1 && Number(trip.agreedValue) > 0) {
          await tx.financialTransaction.create({
            data: {
              companyId: run.companyId,
              vehicleId: run.vehicleId,
              type: 'RECEITA',
              category: trip.type === 'EVENTOS' ? 'FRETAMENTO_EVENTO' : 'FRETAMENTO_TURISMO',
              amount: trip.agreedValue,
              charterTripId: trip.id,
              description: `Receita do serviço ${trip.origin} → ${trip.destination}`,
              date: new Date()
            }
          });
          }
        }
      }
      await tx.vehicle.updateMany({
        where: { id: run.vehicleId, status: { not: 'DANIFICADA' } },
        data: { status: 'PARADO' }
      });
      await tx.vehicleAlert.updateMany({
        where: { serviceRunId: run.id, resolvedAt: null },
        data: { resolvedAt: new Date() }
      });
      await tx.driver.update({
        where: { id: req.user.sub },
        data: { status: 'DISPONIVEL' }
      });
    });
  } catch (error) {
    if (error.message.includes('já foi encerrada')) {
      return res.status(409).json({ error: error.message });
    }
    throw error;
  }
  io.to(`company:${run.companyId}`).emit('run:ended', { runId: run.id, vehicleId: run.vehicleId });
  res.json({ status: 'COMPLETED' });
});

app.post('/vehicles/:vehicleId/manual-attendance', authenticate, async (req, res) => {
  try {
    const vehicle = await accessibleVehicle(req.user, req.params.vehicleId);
    if (!vehicle) return res.status(404).json({ error: 'Veículo não encontrado.' });
    const student = await prisma.student.findFirst({
      where: { id: req.body.studentId, companyId: vehicle.companyId, active: true }
    });
    if (!student || student.vehicleId !== vehicle.id) {
      return res.status(400).json({ error: 'Aluno não está vinculado a esta van.' });
    }
    if (!['IDA', 'VOLTA', 'IDA_E_VOLTA'].includes(req.body.direction)) {
      return res.status(400).json({ error: 'Direção da chamada inválida.' });
    }
    const credits = req.body.direction === 'IDA_E_VOLTA' ? 2 : 1;
    await prisma.$transaction(async tx => {
      const used = await consumeTripCredit(tx, student, credits);
      await tx.studentAttendance.create({
        data: {
          studentId: student.id, vehicleId: vehicle.id,
          date: req.body.date ? new Date(req.body.date) : new Date(),
          direction: req.body.direction, method: 'MANUAL_MOTORISTA', creditsUsed: used
        }
      });
    });
    res.status(201).json({ message: 'Presença registrada.' });
  } catch (error) {
    if (error.message.includes('créditos')) return res.status(409).json({ error: error.message });
    console.error('Falha na chamada manual:', error);
    res.status(400).json({ error: 'Não foi possível registrar a presença.' });
  }
});

app.post('/vehicles/:vehicleId/scan-checkin', authenticate, async (req, res) => {
  try {
    const vehicle = await accessibleVehicle(req.user, req.params.vehicleId);
    if (!vehicle) return res.status(404).json({ error: 'Veículo não encontrado.' });
    const student = await prisma.student.findFirst({
      where: {
        vehicleId: vehicle.id, active: true,
        OR: [{ phone: req.body.phoneOrCode }, { readingCode: req.body.phoneOrCode }]
      }
    });
    if (!student) return res.status(404).json({ error: 'Aluno não reconhecido nesta van.' });
    const direction = req.body.direction || 'IDA';
    if (!['IDA', 'VOLTA', 'IDA_E_VOLTA'].includes(direction)) {
      return res.status(400).json({ error: 'Direção da chamada inválida.' });
    }
    const credits = direction === 'IDA_E_VOLTA' ? 2 : 1;
    await prisma.$transaction(async tx => {
      const used = await consumeTripCredit(tx, student, credits);
      await tx.studentAttendance.create({
        data: {
          studentId: student.id, vehicleId: vehicle.id, direction,
          method: 'QRCODE', creditsUsed: used
        }
      });
    });
    res.status(201).json({ message: `Presença confirmada para ${student.name}.` });
  } catch (error) {
    if (error.message.includes('créditos')) return res.status(409).json({ error: error.message });
    console.error('Falha no check-in QR:', error);
    res.status(400).json({ error: 'Não foi possível registrar o check-in.' });
  }
});

app.get('/companies/:companyId/transactions', authenticate, requireOwner, async (req, res) => {
  try {
    if (!(await companyForUser(req.user, req.params.companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const { date, error } = transactionDateFilter(req.query);
    if (error) return res.status(400).json({ error });
    const where = { companyId: req.params.companyId, ...(date ? { date } : {}) };
    const transactions = await prisma.financialTransaction.findMany({
      where,
      include: {
        vehicle: { select: { id: true, plate: true, model: true } },
        charterTrip: { select: { id: true, clientName: true, origin: true, destination: true } },
        receipt: { select: { fileName: true, mimeType: true, sizeBytes: true } }
      },
      orderBy: { date: 'desc' },
      take: 200
    });
    res.json(transactions);
  } catch (error) {
    console.error('Falha ao carregar lançamentos:', error);
    res.status(500).json({ error: 'Não foi possível carregar os lançamentos.' });
  }
});

app.get('/companies/:companyId/transactions/summary', authenticate, requireOwner, async (req, res) => {
  try {
    if (!(await companyForUser(req.user, req.params.companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const { date, error } = transactionDateFilter(req.query);
    if (error) return res.status(400).json({ error });
    const groups = await prisma.financialTransaction.groupBy({
      by: ['type', 'vehicleId'],
      where: { companyId: req.params.companyId, ...(date ? { date } : {}) },
      _sum: { amount: true },
      _count: { _all: true }
    });
    let revenue = 0;
    let expenses = 0;
    let unallocatedExpenses = 0;
    let transactionCount = 0;
    const expensesByVehicle = new Map();
    for (const group of groups) {
      const amount = Number(group._sum.amount || 0);
      transactionCount += group._count._all;
      if (group.type === 'RECEITA') {
        revenue += amount;
      } else {
        expenses += amount;
        if (group.vehicleId) {
          expensesByVehicle.set(group.vehicleId, amount);
        } else {
          unallocatedExpenses += amount;
        }
      }
    }
    res.json({
      revenue,
      expenses,
      unallocatedExpenses,
      transactionCount,
      expensesByVehicle: [...expensesByVehicle].map(([vehicleId, amount]) => ({
        vehicleId,
        amount
      }))
    });
  } catch (error) {
    console.error('Falha ao calcular resumo financeiro:', error);
    res.status(500).json({ error: 'Não foi possível calcular o resumo financeiro.' });
  }
});

app.post('/transactions', authenticate, requireOwner, async (req, res) => {
  try {
    const { companyId, vehicleId, charterTripId, type, category, amount } = req.body;
    if (!(await companyForUser(req.user, companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    if (!['RECEITA', 'DESPESA'].includes(type) || typeof category !== 'string' || !category.trim()) {
      return res.status(400).json({ error: 'Informe o tipo e a categoria do lançamento.' });
    }
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      return res.status(400).json({ error: 'O valor do lançamento deve ser maior que zero.' });
    }
    const normalizedCategory = category.trim().toUpperCase();
    if (type === 'DESPESA' &&
        ['COMBUSTIVEL', 'MANUTENCAO', 'PNEUS', 'SEGURO'].includes(normalizedCategory) &&
        !vehicleId) {
      return res.status(400).json({ error: 'Selecione a van para este tipo de despesa.' });
    }
    if (vehicleId && !(await prisma.vehicle.findFirst({ where: { id: vehicleId, companyId } }))) {
      return res.status(400).json({ error: 'Veículo não pertence à empresa informada.' });
    }
    if (charterTripId && !(await prisma.charterTrip.findFirst({
      where: {
        id: charterTripId,
        companyId,
        ...(vehicleId ? { vehicleId } : {})
      },
      select: { id: true }
    }))) {
      return res.status(400).json({ error: 'Viagem não pertence à empresa ou à van informada.' });
    }
    const date = req.body.date ? new Date(req.body.date) : new Date();
    if (Number.isNaN(date.getTime())) return res.status(400).json({ error: 'Data inválida.' });
    const transaction = await prisma.financialTransaction.create({
      data: {
        companyId, vehicleId: vehicleId || null, charterTripId: charterTripId || null,
        type, category: normalizedCategory,
        amount: value, description: req.body.description || null, date
      }
    });
    res.status(201).json(transaction);
  } catch (error) {
    console.error('Falha ao criar lançamento:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar o lançamento.' });
  }
});

app.put(
  '/transactions/:transactionId/receipt',
  authenticate,
  requireOwner,
  express.raw({ type: ['image/jpeg', 'image/png'], limit: '5mb' }),
  async (req, res) => {
    try {
      const transaction = await prisma.financialTransaction.findUnique({
        where: { id: req.params.transactionId },
        select: { id: true, companyId: true, type: true }
      });
      if (!transaction || !(await companyForUser(req.user, transaction.companyId))) {
        return res.status(404).json({ error: 'Lançamento não encontrado.' });
      }
      if (transaction.type !== 'DESPESA') {
        return res.status(400).json({ error: 'Comprovantes só podem ser anexados a despesas.' });
      }
      const mimeType = req.get('content-type')?.split(';')[0].trim();
      if (!['image/jpeg', 'image/png'].includes(mimeType) ||
          !Buffer.isBuffer(req.body) || req.body.length === 0) {
        return res.status(415).json({ error: 'Envie uma imagem JPG ou PNG válida.' });
      }
      if (!isValidFinancialReceipt(mimeType, req.body)) {
        return res.status(415).json({ error: 'O conteúdo não corresponde a uma imagem JPG ou PNG.' });
      }
      const fileName = mimeType === 'image/jpeg' ? 'comprovante.jpg' : 'comprovante.png';
      const receipt = await prisma.financialReceipt.upsert({
        where: { transactionId: transaction.id },
        create: {
          transactionId: transaction.id,
          fileName,
          mimeType,
          sizeBytes: req.body.length,
          data: req.body
        },
        update: { fileName, mimeType, sizeBytes: req.body.length, data: req.body }
      });
      res.status(200).json({
        fileName: receipt.fileName,
        mimeType: receipt.mimeType,
        sizeBytes: receipt.sizeBytes
      });
    } catch (error) {
      console.error('Falha ao salvar comprovante:', error);
      res.status(400).json({ error: 'Não foi possível salvar o comprovante.' });
    }
  }
);

app.get('/transactions/:transactionId/receipt', authenticate, requireOwner, async (req, res) => {
  try {
    const transaction = await prisma.financialTransaction.findUnique({
      where: { id: req.params.transactionId },
      include: { receipt: true }
    });
    if (!transaction || !(await companyForUser(req.user, transaction.companyId))) {
      return res.status(404).json({ error: 'Lançamento não encontrado.' });
    }
    if (!transaction.receipt) {
      return res.status(404).json({ error: 'Este lançamento não possui comprovante.' });
    }
    res.set({
      'Content-Type': transaction.receipt.mimeType,
      'Content-Disposition': `inline; filename="${transaction.receipt.fileName}"`,
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.send(Buffer.from(transaction.receipt.data));
  } catch (error) {
    console.error('Falha ao carregar comprovante:', error);
    res.status(500).json({ error: 'Não foi possível carregar o comprovante.' });
  }
});

app.get('/trips/:tripId/financial-summary', authenticate, requireOwner, async (req, res) => {
  const trip = await prisma.charterTrip.findUnique({
    where: { id: req.params.tripId },
    select: { id: true, companyId: true, vehicleId: true, agreedValue: true }
  });
  if (!trip || !(await companyForUser(req.user, trip.companyId))) {
    return res.status(404).json({ error: 'Viagem não encontrada.' });
  }
  const transactions = await prisma.financialTransaction.findMany({
    where: { charterTripId: trip.id },
    orderBy: { date: 'desc' }
  });
  const revenue = transactions
    .filter(item => item.type === 'RECEITA')
    .reduce((total, item) => total + Number(item.amount), 0);
  const expenses = transactions
    .filter(item => item.type === 'DESPESA')
    .reduce((total, item) => total + Number(item.amount), 0);
  res.json({
    agreedValue: Number(trip.agreedValue),
    realizedRevenue: revenue,
    expenses,
    margin: revenue - expenses,
    transactions
  });
});

app.get('/trips/:tripId/passengers', authenticate, async (req, res) => {
  const trip = await prisma.charterTrip.findUnique({
    where: { id: req.params.tripId },
    select: { id: true, companyId: true, driverId: true }
  });
  if (!trip || !(await companyForUser(req.user, trip.companyId)) ||
      (req.user.role === 'DRIVER' && trip.driverId !== req.user.sub)) {
    return res.status(404).json({ error: 'Viagem não encontrada.' });
  }
  const passengers = await prisma.charterPassenger.findMany({
    where: { charterTripId: trip.id },
    orderBy: { name: 'asc' }
  });
  res.json(passengers);
});

app.post('/trips/:tripId/passengers', authenticate, requireOwner, async (req, res) => {
  try {
    const trip = await prisma.charterTrip.findUnique({
      where: { id: req.params.tripId },
      include: { vehicle: { select: { capacity: true } } }
    });
    if (!trip || !(await companyForUser(req.user, trip.companyId))) {
      return res.status(404).json({ error: 'Viagem não encontrada.' });
    }
    if (trip.status !== 'AGENDADO') {
      return res.status(409).json({ error: 'O manifesto só pode ser alterado antes do início da viagem.' });
    }
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (!name) return res.status(400).json({ error: 'Informe o nome do passageiro.' });
    const passenger = await prisma.$transaction(async tx => {
      const count = await tx.charterPassenger.count({
        where: { charterTripId: trip.id }
      });
      if (count >= trip.vehicle.capacity) throw new Error('A viagem atingiu a capacidade de passageiros da van.');
      return tx.charterPassenger.create({
        data: {
          charterTripId: trip.id,
          name,
          phone: typeof req.body.phone === 'string' && req.body.phone.trim()
            ? req.body.phone.trim()
            : null,
          pickupPoint: typeof req.body.pickupPoint === 'string' && req.body.pickupPoint.trim()
            ? req.body.pickupPoint.trim()
            : null,
          notes: typeof req.body.notes === 'string' && req.body.notes.trim()
            ? req.body.notes.trim().slice(0, 500)
            : null
        }
      });
    }, { isolationLevel: 'Serializable' });
    res.status(201).json(passenger);
  } catch (error) {
    if (error.message.includes('capacidade')) return res.status(409).json({ error: error.message });
    if (error.code === 'P2034') {
      return res.status(409).json({ error: 'A lotação foi atualizada por outro usuário; tente novamente.' });
    }
    console.error('Falha ao incluir passageiro:', error);
    res.status(400).json({ error: 'Não foi possível incluir o passageiro.' });
  }
});

app.patch('/trips/:tripId/passengers/:passengerId/status', authenticate, async (req, res) => {
  try {
    const status = req.body.status;
    if (!['EMBARCADO', 'DESEMBARCADO', 'AUSENTE'].includes(status)) {
      return res.status(400).json({ error: 'Status de passageiro inválido.' });
    }
    const trip = await prisma.charterTrip.findUnique({ where: { id: req.params.tripId } });
    if (!trip || !(await companyForUser(req.user, trip.companyId)) ||
        (req.user.role === 'DRIVER' && trip.driverId !== req.user.sub)) {
      return res.status(404).json({ error: 'Viagem não encontrada.' });
    }
    if (req.user.role === 'DRIVER' && trip.status !== 'EM_ANDAMENTO') {
      return res.status(409).json({ error: 'A viagem ainda não está em andamento.' });
    }
    const passenger = await prisma.charterPassenger.findFirst({
      where: { id: req.params.passengerId, charterTripId: trip.id }
    });
    if (!passenger) return res.status(404).json({ error: 'Passageiro não encontrado no manifesto.' });
    res.json(await prisma.charterPassenger.update({
      where: { id: passenger.id },
      data: {
        status,
        boardedAt: status === 'EMBARCADO' ? new Date() : passenger.boardedAt,
        droppedAt: status === 'DESEMBARCADO' ? new Date() : passenger.droppedAt
      }
    }));
  } catch (error) {
    console.error('Falha ao atualizar passageiro:', error);
    res.status(400).json({ error: 'Não foi possível atualizar o status do passageiro.' });
  }
});

app.delete('/trips/:tripId/passengers/:passengerId', authenticate, requireOwner, async (req, res) => {
  const trip = await prisma.charterTrip.findUnique({ where: { id: req.params.tripId } });
  if (!trip || !(await companyForUser(req.user, trip.companyId))) {
    return res.status(404).json({ error: 'Viagem não encontrada.' });
  }
  if (trip.status !== 'AGENDADO') {
    return res.status(409).json({ error: 'O manifesto só pode ser alterado antes do início da viagem.' });
  }
  const deleted = await prisma.charterPassenger.deleteMany({
    where: { id: req.params.passengerId, charterTripId: trip.id }
  });
  if (!deleted.count) return res.status(404).json({ error: 'Passageiro não encontrado.' });
  res.status(204).end();
});

app.post('/trips', authenticate, requireOwner, async (req, res) => {
  try {
    const { companyId, vehicleId, driverId, type, departureDate, returnDate, agreedValue } = req.body;
    if (!(await companyForUser(req.user, companyId))) {
      return res.status(404).json({ error: 'Empresa não encontrada.' });
    }
    const vehicle = await prisma.vehicle.findFirst({ where: { id: vehicleId, companyId } });
    if (!vehicle || !['TURISMO', 'EVENTOS'].includes(type) || !vehicle.purposes.includes(type)) {
      return res.status(400).json({ error: 'Veículo ou finalidade inválidos para esta viagem.' });
    }
    if (typeof driverId !== 'string' || !(await prisma.driver.findFirst({
      where: { id: driverId, companyId, active: true }
    }))) return res.status(400).json({ error: 'Selecione um motorista ativo da empresa.' });
    if (![req.body.clientName, req.body.clientPhone, req.body.origin, req.body.destination]
      .every(value => typeof value === 'string' && value.trim())) {
      return res.status(400).json({ error: 'Informe cliente, telefone, origem e destino.' });
    }
    const departure = new Date(departureDate);
    const returnAt = new Date(returnDate);
    const value = Number(agreedValue);
    if (Number.isNaN(departure.getTime()) || Number.isNaN(returnAt.getTime()) ||
        returnAt < departure || !Number.isFinite(value) || value < 0) {
      return res.status(400).json({ error: 'Datas ou valor da viagem inválidos.' });
    }
    const conflict = await prisma.charterTrip.findFirst({
      where: {
        companyId,
        status: { in: ['AGENDADO', 'EM_ANDAMENTO'] },
        departureDate: { lt: returnAt },
        returnDate: { gt: departure },
        OR: [{ vehicleId }, { driverId }]
      },
      select: { id: true, vehicleId: true, driverId: true }
    });
    if (conflict) {
      return res.status(409).json({
        error: conflict.vehicleId === vehicleId
          ? 'A van já possui um serviço neste período.'
          : 'O motorista já está escalado neste período.'
      });
    }
    const trip = await prisma.charterTrip.create({
      data: {
        companyId, vehicleId, driverId, type,
        clientName: req.body.clientName, clientDoc: req.body.clientDoc || null,
        clientPhone: req.body.clientPhone, origin: req.body.origin,
        destination: req.body.destination, departureDate: departure,
        returnDate: returnAt, agreedValue: value, notes: req.body.notes || null
      }
    });
    res.status(201).json(trip);
  } catch (error) {
    console.error('Falha ao criar viagem:', error);
    res.status(400).json({ error: 'Não foi possível cadastrar a viagem.' });
  }
});

app.use((error, _req, res, _next) => {
  console.error('Erro inesperado na API:', error);
  const status = error.status === 413 ? 413 : 500;
  res.status(status).json({
    error: status === 413
      ? 'O arquivo excede o limite de 5 MB.'
      : 'Erro interno. Tente novamente mais tarde.'
  });
});
app.get('/cron/monitor-locations', async (req, res) => {
  try {
    await monitorActiveRunLocations();
    await prisma.vehicleLocationSample.deleteMany({
      where: { createdAt: { lt: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) } }
    });
    res.json({ status: 'Manutenção de rotas e GPS concluída.' });
  } catch (error) {
    console.error('Falha na manutenção:', error);
    res.status(500).json({ error: 'Erro na manutenção' });
  }
});


module.exports = app;


if (process.env.NODE_ENV !== 'production' && require.main === module) {
  app.listen(PORT, () => console.log(`🚐 API rodando localmente na porta ${PORT}`));
}