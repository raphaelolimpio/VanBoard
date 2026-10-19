/*
  Warnings:

  - A unique constraint covering the columns `[readingCode]` on the table `Student` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "BillingType" AS ENUM ('MENSAL', 'POR_VIAGEM');

-- CreateEnum
CREATE TYPE "TripDirection" AS ENUM ('IDA', 'VOLTA', 'IDA_E_VOLTA');

-- CreateEnum
CREATE TYPE "CheckInMethod" AS ENUM ('QRCODE', 'MANUAL_MOTORISTA');

-- AlterTable
ALTER TABLE "Student" ADD COLUMN     "billingType" "BillingType" NOT NULL DEFAULT 'MENSAL',
ADD COLUMN     "hasCellphone" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "pricePerTrip" DECIMAL(10,2),
ADD COLUMN     "readingCode" TEXT,
ADD COLUMN     "tripCredits" INTEGER NOT NULL DEFAULT 0,
ALTER COLUMN "monthlyFee" DROP NOT NULL,
ALTER COLUMN "dueDay" DROP NOT NULL;

-- CreateTable
CREATE TABLE "StudentAttendance" (
    "id" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "direction" "TripDirection" NOT NULL,
    "method" "CheckInMethod" NOT NULL,
    "creditsUsed" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "StudentAttendance_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Student_readingCode_key" ON "Student"("readingCode");

-- AddForeignKey
ALTER TABLE "StudentAttendance" ADD CONSTRAINT "StudentAttendance_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "Student"("id") ON DELETE CASCADE ON UPDATE CASCADE;
