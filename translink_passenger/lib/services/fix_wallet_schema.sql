
ALTER TABLE fare_transactions
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'success';

ALTER TABLE fare_transactions
ADD COLUMN IF NOT EXISTS description TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Passengers can view own transactions') THEN
        CREATE POLICY "Passengers can view own transactions"
        ON fare_transactions FOR SELECT
        TO authenticated
        USING (auth.uid() = passenger_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Passengers can insert own transactions') THEN
        CREATE POLICY "Passengers can insert own transactions"
        ON fare_transactions FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = passenger_id);
    END IF;
END $$;