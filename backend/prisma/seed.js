const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');
const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Populando banco de dados boardVan...');
  const seedPassword = process.env.SEED_OWNER_PASSWORD;
  if (!seedPassword || seedPassword.length < 8) {
    throw new Error('Defina SEED_OWNER_PASSWORD com pelo menos 8 caracteres antes de executar o seed.');
  }

  // 1. Cria Proprietário e Empresa
  const owner = await prisma.owner.upsert({
    where: { email: 'admin@boardvan.com' },
    update: { passwordHash: await bcrypt.hash(seedPassword, 12) },
    create: {
      name: 'Proprietário Exemplo',
      email: 'admin@boardvan.com',
      passwordHash: await bcrypt.hash(seedPassword, 12)
    }
  });

  const company = await prisma.company.create({
    data: {
      name: 'Expresso Tocantins Vans',
      cnpj: '12.345.678/0001-99',
      ownerId: owner.id
    }
  });

  // 2. Cria Motoristas
  const driverEscolar = await prisma.driver.create({
    data: {
      companyId: company.id,
      name: 'Carlos Eduardo',
      cnh: '11122233344',
      cnhCategory: 'D',
      phone: '63999990001',
      status: 'DISPONIVEL'
    }
  });

  const driverTurismo = await prisma.driver.create({
    data: {
      companyId: company.id,
      name: 'Marcos Roberto',
      cnh: '55566677788',
      cnhCategory: 'D',
      phone: '63999990002',
      status: 'EM_VIAGEM'
    }
  });

  // 3. Cria Van 1: Finalidade ESCOLAR
  const vanEscolar = await prisma.vehicle.create({
    data: {
      companyId: company.id,
      plate: 'QWA-1020',
      model: 'Mercedes-Benz Sprinter 416',
      year: 2024,
      capacity: 15,
      description: 'Van Escolar Ar-Condicionado e Bancos Reclináveis',
      status: 'RODANDO',
      purposes: ['ESCOLAR'],
      defaultDriverId: driverEscolar.id
    }
  });

  // Cadastra Alunos e Rota na Van Escolar
  await prisma.student.createMany({
    data: [
      {
        companyId: company.id,
        vehicleId: vanEscolar.id,
        name: 'Lucas Silva',
        guardian: 'Ana Silva',
        phone: '63988881111',
        pickupAddr: 'Quadra 104 Sul, Alameda 2',
        schoolName: 'Colégio Marista',
        shift: 'MANHA',
        monthlyFee: 450.00,
        dueDay: 10
      },
      {
        companyId: company.id,
        vehicleId: vanEscolar.id,
        name: 'Beatriz Costa',
        guardian: 'Roberto Costa',
        phone: '63988882222',
        pickupAddr: 'Quadra 206 Sul, Av. LO-03',
        schoolName: 'Colégio Marista',
        shift: 'MANHA',
        monthlyFee: 450.00,
        dueDay: 10
      }
    ]
  });

  await prisma.schoolRoute.create({
    data: {
      vehicleId: vanEscolar.id,
      name: 'Rota Sul -> Colégio Marista (Manhã)',
      shift: 'MANHA',
      startTime: '06:20',
      endTime: '07:15',
      stopsOrder: ['Quadra 104 Sul', 'Quadra 206 Sul', 'Colégio Marista']
    }
  });

  // 4. Cria Van 2: Finalidade TURISMO e EVENTOS
  const vanTurismo = await prisma.vehicle.create({
    data: {
      companyId: company.id,
      plate: 'TOV-5060',
      model: 'Renault Master Executiva',
      year: 2025,
      capacity: 16,
      description: 'Van Executiva Turismo c/ Wi-Fi, TV e Frigobar',
      status: 'PARADO',
      purposes: ['TURISMO', 'EVENTOS'],
      defaultDriverId: driverTurismo.id
    }
  });

  await prisma.charterTrip.create({
    data: {
      companyId: company.id,
      vehicleId: vanTurismo.id,
      driverId: driverTurismo.id,
      type: 'TURISMO',
      clientName: 'Agência Jalapão Ecotour',
      clientDoc: '98.765.432/0001-10',
      clientPhone: '63977773333',
      origin: 'Palmas - TO',
      destination: 'Taquaruçu / Cachoeiras',
      departureDate: new Date('2026-10-24T07:00:00Z'),
      returnDate: new Date('2026-10-25T19:00:00Z'),
      agreedValue: 2800.00,
      notes: 'Grupo de 12 turistas. Incluso parada para almoço.',
      status: 'AGENDADO'
    }
  });

  // 5. Lança Transações Financeiras (Receitas e Despesas)
  await prisma.financialTransaction.createMany({
    data: [
      {
        companyId: company.id,
        vehicleId: vanEscolar.id,
        type: 'RECEITA',
        category: 'MENSALIDADE_ESCOLAR',
        amount: 900.00,
        description: 'Mensalidades Outubro (2 alunos)'
      },
      {
        companyId: company.id,
        vehicleId: vanTurismo.id,
        type: 'RECEITA',
        category: 'FRETAMENTO',
        amount: 2800.00,
        description: 'Sinal + Pagamento Fretamento Agência Ecotour'
      },
      {
        companyId: company.id,
        vehicleId: vanEscolar.id,
        type: 'DESPESA',
        category: 'COMBUSTIVEL',
        amount: 650.00,
        description: 'Abastecimento Diesel S10'
      }
    ]
  });

  console.log('✅ Dados criados com sucesso!');
  console.log('📌 ID da Empresa para testar no navegador:', company.id);
  console.log('🚐 ID da Van Escolar:', vanEscolar.id);
  console.log('🚌 ID da Van Turismo:', vanTurismo.id);
}

main()
  .catch(e => console.error(e))
  .finally(async () => await prisma.$disconnect());