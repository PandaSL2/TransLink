-- Migration 011: Live Data Cleanup
CREATE OR REPLACE FUNCTION delete_stale_bus_positions()
RETURNS VOID AS $$
BEGIN
    DELETE FROM public.live_bus_positions
    WHERE last_updated_at < NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;
