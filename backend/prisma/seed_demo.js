const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');
const prisma = new PrismaClient();

async function main() {
  const demoEmail = process.env.SEED_DEMO_EMAIL;
  const demoPassword = process.env.SEED_DEMO_PASSWORD;
  if (!demoEmail || !demoPassword || demoPassword.length < 8) {
    console.log('Defina SEED_DEMO_EMAIL e SEED_DEMO_PASSWORD (>=8) antes de executar este script.');
    process.exit(1);
  }

  console.log('🌱 Criando conta demo para', demoEmail);

  const demoOwner = await prisma.owner.upsert({
    where: { email: demoEmail },
    update: { passwordHash: await bcrypt.hash(demoPassword, 12) },
    create: {
      name: 'Murdok Demo',
      email: demoEmail,
      passwordHash: await bcrypt.hash(demoPassword, 12),
    }
  });

  const demoCompany = await prisma.company.create({
    data: { name: 'Murdok Demo Transportes', cnpj: null, ownerId: demoOwner.id }
  });

  const demoDriver = await prisma.driver.create({
    data: {
      companyId: demoCompany.id,
      name: 'Raphael Murdok',
      cnh: '00011122233',
      cnhCategory: 'D',
      phone: '63970000001',
      email: demoEmail,
      passwordHash: await bcrypt.hash(demoPassword, 12),
      status: 'DISPONIVEL'
    }
  });

  const demoVan = await prisma.vehicle.create({
    data: {
      companyId: demoCompany.id,
      plate: 'MRD-2026',
      model: 'Fiat Ducato Demo',
      year: 2026,
      capacity: 14,
      description: 'Van demo para visualização',
      status: 'PARADO',
      purposes: ['TURISMO', 'EVENTOS'],
      defaultDriverId: demoDriver.id
    }
  });

  await prisma.student.createMany({
    data: [
      {
        companyId: demoCompany.id,
        vehicleId: demoVan.id,
        name: 'Aluno Demo 1',
        guardian: 'Responsavel Demo',
        phone: '63970100001',
        pickupAddr: 'Rua Demo, 100',
        schoolName: 'Escola Demo',
        shift: 'MANHA',
        monthlyFee: 350.00,
        dueDay: 5
      },
      {
        companyId: demoCompany.id,
        vehicleId: demoVan.id,
        name: 'Artista Fulano',
        guardian: 'Produção Evento',
        phone: '63970100002',
        pickupAddr: 'Teatro Municipal',
        schoolName: '—',
        shift: 'INTEGRAL',
        billingType: 'POR_VIAGEM',
        pricePerTrip: 250.00,
        tripCredits: 3
      }
    ]
  });

  await prisma.charterTrip.create({
    data: {
      companyId: demoCompany.id,
      vehicleId: demoVan.id,
      driverId: demoDriver.id,
      type: 'EVENTOS',
      clientName: 'Produtora Demo',
      clientPhone: '63970200001',
      origin: 'Cidade A',
      destination: 'Teatro Municipal',
      departureDate: new Date(Date.now() + 24 * 60 * 60 * 1000),
      returnDate: new Date(Date.now() + 24 * 60 * 60 * 1000 + 6 * 60 * 60 * 1000),
      agreedValue: 1200.00,
      notes: 'Transporte para show demo',
      status: 'AGENDADO'
    }
  });

  await prisma.financialTransaction.create({
    data: {
      companyId: demoCompany.id,
      vehicleId: demoVan.id,
      type: 'RECEITA',
      category: 'FRETAMENTO',
      amount: 1200.00,
      description: 'Fretamento Demo (evento)'
    }
  });

  console.log('✅ Conta demo criada:', demoEmail);
  console.log('📌 Company ID (demo):', demoCompany.id);
  console.log('🚐 Demo Van ID:', demoVan.id);
}

main()
  .catch(e => console.error(e))
  .finally(async () => await prisma.$disconnect());
