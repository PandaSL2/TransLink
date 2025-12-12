-- Fix for missing 'status' column in fare_transactions
ALTER TABLE fare_transactions 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'success';

-- Ensure description column also exists
ALTER TABLE fare_transactions 
ADD COLUMN IF NOT EXISTS description TEXT;

-- Update RLS policies for fare_transactions
-- Allow passengers to select their own transactions
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
