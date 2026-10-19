-- CreateEnum
CREATE TYPE "PassengerStatus" AS ENUM ('AGUARDANDO', 'EMBARCADO', 'DESEMBARCADO', 'AUSENTE');

-- AlterTable
ALTER TABLE "FinancialTransaction" ADD COLUMN     "charterTripId" TEXT;

-- AlterTable
ALTER TABLE "SchoolRoute" ADD COLUMN     "daysOfWeek" INTEGER[] DEFAULT ARRAY[1, 2, 3, 4, 5]::INTEGER[],
ADD COLUMN     "schoolLatitude" DOUBLE PRECISION,
ADD COLUMN     "schoolLongitude" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "DriverInvite" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "acceptedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DriverInvite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StudentTrackingGrant" (
    "id" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "consentAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StudentTrackingGrant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharterPassenger" (
    "id" TEXT NOT NULL,
    "charterTripId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "pickupPoint" TEXT,
    "notes" TEXT,
    "status" "PassengerStatus" NOT NULL DEFAULT 'AGUARDANDO',
    "boardedAt" TIMESTAMP(3),
    "droppedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CharterPassenger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VehicleDocument" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VehicleDocument_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VehicleInspection" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "serviceRunId" TEXT,
    "tiresOk" BOOLEAN NOT NULL,
    "lightsOk" BOOLEAN NOT NULL,
    "brakesOk" BOOLEAN NOT NULL,
    "documentsOk" BOOLEAN NOT NULL,
    "cleanlinessOk" BOOLEAN NOT NULL,
    "notes" TEXT,
    "blocked" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VehicleInspection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VehicleLocationSample" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "serviceRunId" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "heading" DOUBLE PRECISION,
    "speed" DOUBLE PRECISION,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VehicleLocationSample_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VehicleAlert" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "serviceRunId" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "acknowledgedAt" TIMESTAMP(3),
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VehicleAlert_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DriverInvite_codeHash_key" ON "DriverInvite"("codeHash");

-- CreateIndex
CREATE INDEX "DriverInvite_driverId_expiresAt_idx" ON "DriverInvite"("driverId", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "StudentTrackingGrant_codeHash_key" ON "StudentTrackingGrant"("codeHash");

-- CreateIndex
CREATE INDEX "StudentTrackingGrant_studentId_expiresAt_idx" ON "StudentTrackingGrant"("studentId", "expiresAt");

-- CreateIndex
CREATE INDEX "CharterPassenger_charterTripId_status_idx" ON "CharterPassenger"("charterTripId", "status");

-- CreateIndex
CREATE INDEX "VehicleDocument_vehicleId_expiresAt_idx" ON "VehicleDocument"("vehicleId", "expiresAt");

-- CreateIndex
CREATE INDEX "VehicleInspection_vehicleId_createdAt_idx" ON "VehicleInspection"("vehicleId", "createdAt");

-- CreateIndex
CREATE INDEX "VehicleLocationSample_serviceRunId_createdAt_idx" ON "VehicleLocationSample"("serviceRunId", "createdAt");

-- CreateIndex
CREATE INDEX "VehicleLocationSample_createdAt_idx" ON "VehicleLocationSample"("createdAt");

-- CreateIndex
CREATE INDEX "VehicleAlert_companyId_acknowledgedAt_createdAt_idx" ON "VehicleAlert"("companyId", "acknowledgedAt", "createdAt");

-- CreateIndex
CREATE INDEX "VehicleAlert_serviceRunId_kind_createdAt_idx" ON "VehicleAlert"("serviceRunId", "kind", "createdAt");

-- AddForeignKey
ALTER TABLE "DriverInvite" ADD CONSTRAINT "DriverInvite_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverInvite" ADD CONSTRAINT "DriverInvite_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StudentTrackingGrant" ADD CONSTRAINT "StudentTrackingGrant_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "Student"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CharterPassenger" ADD CONSTRAINT "CharterPassenger_charterTripId_fkey" FOREIGN KEY ("charterTripId") REFERENCES "CharterTrip"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleDocument" ADD CONSTRAINT "VehicleDocument_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleInspection" ADD CONSTRAINT "VehicleInspection_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleInspection" ADD CONSTRAINT "VehicleInspection_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleInspection" ADD CONSTRAINT "VehicleInspection_serviceRunId_fkey" FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleLocationSample" ADD CONSTRAINT "VehicleLocationSample_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleLocationSample" ADD CONSTRAINT "VehicleLocationSample_serviceRunId_fkey" FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleAlert" ADD CONSTRAINT "VehicleAlert_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleAlert" ADD CONSTRAINT "VehicleAlert_serviceRunId_fkey" FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleAlert" ADD CONSTRAINT "VehicleAlert_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FinancialTransaction" ADD CONSTRAINT "FinancialTransaction_charterTripId_fkey" FOREIGN KEY ("charterTripId") REFERENCES "CharterTrip"("id") ON DELETE SET NULL ON UPDATE CASCADE;
