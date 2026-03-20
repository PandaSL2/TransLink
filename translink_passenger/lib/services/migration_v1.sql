
ALTER TABLE fare_transactions
ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE fare_transactions
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'success';

CREATE OR REPLACE FUNCTION handle_topup(
  p_user_id UUID,
  p_amount NUMERIC(10,2),
  p_description TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_balance NUMERIC(10,2);
BEGIN

  INSERT INTO passenger_wallets (user_id, balance)
  VALUES (p_user_id, p_amount)
  ON CONFLICT (user_id)
  DO UPDATE SET balance = passenger_wallets.balance + EXCLUDED.balance
  RETURNING balance INTO v_new_balance;

  INSERT INTO fare_transactions (passenger_id, amount, type, description, status)
  VALUES (p_user_id, p_amount, 'credit', p_description, 'success');

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', v_new_balance
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

CREATE OR REPLACE FUNCTION process_payment(
  p_passenger_id UUID,
  p_amount NUMERIC(10,2),
  p_bus_id TEXT,
  p_route_number TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_balance NUMERIC(10,2);
BEGIN

  SELECT balance INTO v_current_balance FROM passenger_wallets WHERE user_id = p_passenger_id;

  IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient funds');
  END IF;

  UPDATE passenger_wallets
  SET balance = balance - p_amount
  WHERE user_id = p_passenger_id;

  INSERT INTO fare_transactions (passenger_id, amount, type, description, status)
  VALUES (p_passenger_id, p_amount, 'debit', 'Bus Fare - ' || p_route_number, 'success');

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;