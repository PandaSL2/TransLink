-- Migration to add historical logs for ML training
CREATE TABLE IF NOT EXISTS travel_time_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_number TEXT NOT NULL,
    bus_number TEXT NOT NULL,
    start_stop_id UUID REFERENCES stops(id),
    end_stop_id UUID REFERENCES stops(id),
    actual_duration_minutes INTEGER NOT NULL,
    hour_of_day INTEGER NOT NULL,
    day_of_week INTEGER NOT NULL,
    weather_condition TEXT DEFAULT 'clear',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster querying during model updates
CREATE INDEX IF NOT EXISTS idx_travel_logs_route ON travel_time_logs(route_number);
CREATE INDEX IF NOT EXISTS idx_travel_logs_time ON travel_time_logs(hour_of_day, day_of_week);

-- Function to get average travel time (The "Heuristic Model")
CREATE OR REPLACE FUNCTION get_predicted_travel_time(
    p_route_number TEXT,
    p_start_stop_id UUID,
    p_end_stop_id UUID,
    p_hour INTEGER
) RETURNS TABLE (avg_duration NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT AVG(actual_duration_minutes)::NUMERIC
    FROM travel_time_logs
    WHERE route_number = p_route_number
      AND start_stop_id = p_start_stop_id
      AND end_stop_id = p_end_stop_id
      AND hour_of_day BETWEEN p_hour - 1 AND p_hour + 1;
END;
$$ LANGUAGE plpgsql;
