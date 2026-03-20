

CREATE OR REPLACE FUNCTION handle_payment(
    p_passenger_id UUID,
    p_amount NUMERIC(10,2),
    p_bus_number TEXT,
    p_route_number TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_bal NUMERIC(10,2);
    txn_id UUID;
BEGIN

    SELECT balance INTO current_bal
    FROM public.passenger_wallets
    WHERE user_id = p_passenger_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Passenger wallet not found');
    END IF;

    IF current_bal < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient balance');
    END IF;

    UPDATE public.passenger_wallets
    SET balance = balance - p_amount,
        updated_at = NOW()
    WHERE user_id = p_passenger_id;

    INSERT INTO public.fare_transactions (
        passenger_id,
        amount,
        bus_number,
        route_number,
        type,
        status,
        description,
        created_at
    ) VALUES (
        p_passenger_id,
        p_amount,
        p_bus_number,
        p_route_number,
        'debit',
        'success',
        'Bus Fare - Route ' || p_route_number,
        NOW()
    ) RETURNING id INTO txn_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', txn_id,
        'new_balance', (current_bal - p_amount)
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;