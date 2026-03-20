

DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN (SELECT policyname FROM pg_policies WHERE tablename = 'live_bus_positions') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON live_bus_positions', pol.policyname);
    END LOOP;
END $$;

ALTER TABLE live_bus_positions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public Read Live Buses" ON live_bus_positions
    FOR SELECT USING (true);

CREATE POLICY "Authenticated Drivers Upsert" ON live_bus_positions
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Anon Drivers Upsert" ON live_bus_positions
    FOR ALL TO anon
    USING (true)
    WITH CHECK (true);

BEGIN;

    DROP PUBLICATION IF EXISTS supabase_realtime;
    CREATE PUBLICATION supabase_realtime FOR TABLE live_bus_positions;
COMMIT;

ALTER TABLE live_bus_positions REPLICA IDENTITY FULL;

TRUNCATE TABLE live_bus_positions;

