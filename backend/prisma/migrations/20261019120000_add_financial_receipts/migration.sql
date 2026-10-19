CREATE TABLE "FinancialReceipt" (
    "id" TEXT NOT NULL,
    "transactionId" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "data" BYTEA NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FinancialReceipt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FinancialReceipt_transactionId_key"
ON "FinancialReceipt"("transactionId");

ALTER TABLE "FinancialReceipt"
ADD CONSTRAINT "FinancialReceipt_transactionId_fkey"
FOREIGN KEY ("transactionId") REFERENCES "FinancialTransaction"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
