CREATE TYPE "ServiceRunStatus" AS ENUM ('PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED');
CREATE TYPE "EmergencyStatus" AS ENUM ('OPEN', 'ACCEPTED', 'RESOLVED', 'CANCELLED');
CREATE TYPE "EmergencyOfferStatus" AS ENUM ('PENDING', 'ACCEPTED', 'DECLINED', 'EXPIRED');

ALTER TABLE "Driver"
ADD COLUMN "email" TEXT,
ADD COLUMN "passwordHash" TEXT,
ADD COLUMN "active" BOOLEAN NOT NULL DEFAULT true;

CREATE UNIQUE INDEX "Driver_email_key" ON "Driver"("email");
ALTER TABLE "StudentAttendance" ADD COLUMN "serviceRunId" TEXT;

CREATE TABLE "VehicleLocation" (
  "vehicleId" TEXT NOT NULL,
  "latitude" DOUBLE PRECISION NOT NULL,
  "longitude" DOUBLE PRECISION NOT NULL,
  "accuracy" DOUBLE PRECISION,
  "heading" DOUBLE PRECISION,
  "speed" DOUBLE PRECISION,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "VehicleLocation_pkey" PRIMARY KEY ("vehicleId")
);

CREATE TABLE "ServiceRun" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "vehicleId" TEXT NOT NULL,
  "driverId" TEXT NOT NULL,
  "routeId" TEXT,
  "charterTripId" TEXT,
  "purpose" "VehiclePurpose" NOT NULL,
  "status" "ServiceRunStatus" NOT NULL DEFAULT 'PLANNED',
  "startedAt" TIMESTAMP(3),
  "endedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ServiceRun_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "StudentRunAssignment" (
  "id" TEXT NOT NULL,
  "serviceRunId" TEXT NOT NULL,
  "studentId" TEXT NOT NULL,
  "assignedVehicleId" TEXT NOT NULL,
  "temporary" BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT "StudentRunAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EmergencyRequest" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "serviceRunId" TEXT NOT NULL,
  "replacementRunId" TEXT,
  "brokenVehicleId" TEXT NOT NULL,
  "studentId" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "status" "EmergencyStatus" NOT NULL DEFAULT 'OPEN',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolvedAt" TIMESTAMP(3),
  CONSTRAINT "EmergencyRequest_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EmergencyOffer" (
  "id" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "vehicleId" TEXT NOT NULL,
  "distanceMeters" DOUBLE PRECISION,
  "status" "EmergencyOfferStatus" NOT NULL DEFAULT 'PENDING',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "respondedAt" TIMESTAMP(3),
  CONSTRAINT "EmergencyOffer_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StudentAttendance_serviceRunId_studentId_direction_key"
ON "StudentAttendance"("serviceRunId", "studentId", "direction");

CREATE UNIQUE INDEX "StudentRunAssignment_serviceRunId_studentId_key"
ON "StudentRunAssignment"("serviceRunId", "studentId");
CREATE INDEX "StudentRunAssignment_assignedVehicleId_serviceRunId_idx"
ON "StudentRunAssignment"("assignedVehicleId", "serviceRunId");
CREATE INDEX "ServiceRun_companyId_status_idx" ON "ServiceRun"("companyId", "status");
CREATE INDEX "ServiceRun_driverId_status_idx" ON "ServiceRun"("driverId", "status");
CREATE INDEX "EmergencyRequest_companyId_status_idx" ON "EmergencyRequest"("companyId", "status");
CREATE UNIQUE INDEX "EmergencyOffer_requestId_vehicleId_key"
ON "EmergencyOffer"("requestId", "vehicleId");
CREATE INDEX "EmergencyOffer_vehicleId_status_idx" ON "EmergencyOffer"("vehicleId", "status");

ALTER TABLE "VehicleLocation" ADD CONSTRAINT "VehicleLocation_vehicleId_fkey"
FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ServiceRun" ADD CONSTRAINT "ServiceRun_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ServiceRun" ADD CONSTRAINT "ServiceRun_vehicleId_fkey"
FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ServiceRun" ADD CONSTRAINT "ServiceRun_driverId_fkey"
FOREIGN KEY ("driverId") REFERENCES "Driver"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ServiceRun" ADD CONSTRAINT "ServiceRun_routeId_fkey"
FOREIGN KEY ("routeId") REFERENCES "SchoolRoute"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ServiceRun" ADD CONSTRAINT "ServiceRun_charterTripId_fkey"
FOREIGN KEY ("charterTripId") REFERENCES "CharterTrip"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "StudentRunAssignment" ADD CONSTRAINT "StudentRunAssignment_serviceRunId_fkey"
FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "StudentRunAssignment" ADD CONSTRAINT "StudentRunAssignment_studentId_fkey"
FOREIGN KEY ("studentId") REFERENCES "Student"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "StudentRunAssignment" ADD CONSTRAINT "StudentRunAssignment_assignedVehicleId_fkey"
FOREIGN KEY ("assignedVehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "StudentAttendance" ADD CONSTRAINT "StudentAttendance_serviceRunId_fkey"
FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "EmergencyRequest" ADD CONSTRAINT "EmergencyRequest_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmergencyRequest" ADD CONSTRAINT "EmergencyRequest_serviceRunId_fkey"
FOREIGN KEY ("serviceRunId") REFERENCES "ServiceRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmergencyRequest" ADD CONSTRAINT "EmergencyRequest_replacementRunId_fkey"
FOREIGN KEY ("replacementRunId") REFERENCES "ServiceRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "EmergencyRequest" ADD CONSTRAINT "EmergencyRequest_brokenVehicleId_fkey"
FOREIGN KEY ("brokenVehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmergencyRequest" ADD CONSTRAINT "EmergencyRequest_studentId_fkey"
FOREIGN KEY ("studentId") REFERENCES "Student"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmergencyOffer" ADD CONSTRAINT "EmergencyOffer_requestId_fkey"
FOREIGN KEY ("requestId") REFERENCES "EmergencyRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmergencyOffer" ADD CONSTRAINT "EmergencyOffer_vehicleId_fkey"
FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
