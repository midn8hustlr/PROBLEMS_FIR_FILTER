import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


# Full 120-tap symmetric coefficients: H[k] = k+1 for k=0..59, mirrored
H = list(range(1, 61)) + list(range(60, 0, -1))


def to_signed(val, bits=23):
    """Convert unsigned value to signed interpretation."""
    if val >= (1 << (bits - 1)):
        val -= (1 << bits)
    return val


async def _run_impulse_test(dut, impulse_value, label):
    """Shared impulse response test logic.

    Applies a single impulse of `impulse_value` at x[0] and verifies
    that every decimated output matches h[k] * impulse_value.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.x_in.value = 0

    for _ in range(5):
        await FallingEdge(dut.clk)

    dut.rst_n.value = 1

    dut._log.info(f"{label}: Impulse Response (impulse = {impulse_value})")
    dut._log.info("-" * 50)

    # Apply impulse at x[0]
    dut.x_in.value = impulse_value
    await FallingEdge(dut.clk)
    dut.x_in.value = 0
    await FallingEdge(dut.clk)

    # Detect first non-zero output to determine phase alignment
    # Allow up to 10 cycles latency
    first_phase = -1
    for _ in range(10):
        y_val = to_signed(dut.y_out.value.to_unsigned(), 23)
        if y_val != 0:
            for p in range(3):
                if y_val == H[p] * impulse_value:
                    first_phase = p
                    dut._log.info(f"Detected phase alignment: {p} (first output = {y_val})")
                    break
            assert first_phase >= 0, \
                f"First output {y_val} doesn't match any phase: " \
                f"expected one of {[H[p]*impulse_value for p in range(3)]}"
            break
        await FallingEdge(dut.clk)

    assert first_phase >= 0, "Filter latency too high (>10 cycles)"

    # Verify remaining impulse response outputs
    test_count = 1
    pass_count = 1

    tap_idx = first_phase + 3
    while tap_idx < 120:
        # Wait 3 cycles for next output
        for _ in range(3):
            await FallingEdge(dut.clk)

        y_val = to_signed(dut.y_out.value.to_unsigned(), 23)
        expected = H[tap_idx] * impulse_value
        test_count += 1

        if y_val == expected:
            pass_count += 1
            dut._log.info(f"  h[{tap_idx}]={H[tap_idx]}: y_out={y_val} [PASS]")
        else:
            dut._log.error(f"  h[{tap_idx}]={H[tap_idx]}: y_out={y_val}, expected={expected} [FAIL]")

        tap_idx += 3

    dut._log.info(f"Impulse test: {pass_count}/{test_count} passed")
    assert pass_count == test_count, f"Impulse response test failed: {pass_count}/{test_count} passed"


@cocotb.test()
async def test_impulse_response_unit(dut):
    """Test 1a: Unit Impulse Response - impulse of 1 at x[0].

    Verifies the raw coefficient values at every decimated output tap.
    Useful for debugging since expected values equal the coefficients directly.
    """
    await _run_impulse_test(dut, impulse_value=1, label="Test 1a")


@cocotb.test()
async def test_impulse_response_scaled(dut):
    """Test 1b: Scaled Impulse Response - impulse of 127 at x[0].

    Verifies the filter output for a full-scale impulse, checking that
    h[k] * 127 appears correctly at each decimated output tap.
    """
    await _run_impulse_test(dut, impulse_value=127, label="Test 1b")


@cocotb.test()
async def test_impulse_response_negative(dut):
    """Test 1c: Negative Impulse Response - impulse of -127 at x[0].

    Verifies the filter output for a full-scale negative impulse, checking
    that h[k] * (-127) appears correctly at each decimated output tap.
    """
    await _run_impulse_test(dut, impulse_value=-127, label="Test 1c")


async def _run_step_test(dut, step_value, label):
    """Shared step response test logic.

    Applies a constant input of `step_value` and verifies that the filter
    settles to sum(H) * step_value.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.x_in.value = step_value

    dut.rst_n.value = 0
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    dut._log.info(f"{label}: Step Response (x[n] = {step_value} for all n)")
    dut._log.info("-" * 50)

    # Wait for filter to settle (120 taps + pipeline latency)
    for _ in range(140):
        await FallingEdge(dut.clk)

    expected = sum(H) * step_value
    y_val = to_signed(dut.y_out.value.to_unsigned(), 23)

    dut._log.info(f"  Final result = {y_val}, expected = {expected}")

    if y_val == expected:
        dut._log.info("  Step response [PASS]")
    else:
        dut._log.error(f"  Step response [FAIL]: got {y_val}, expected {expected}")

    assert y_val == expected, f"Step response test failed: got {y_val}, expected {expected}"


@cocotb.test()
async def test_step_response_unit(dut):
    """Test 2a: Unit Step Response - x[n] = 1 for all n.

    Verifies steady-state output equals sum(H). Useful for debugging
    since the expected value is just the sum of all coefficients.
    """
    await _run_step_test(dut, step_value=1, label="Test 2a")


@cocotb.test()
async def test_step_response_scaled(dut):
    """Test 2b: Scaled Step Response - x[n] = 127 for all n.

    Verifies steady-state output equals sum(H) * 127, exercising
    full-scale input to catch overflow/truncation issues.
    """
    await _run_step_test(dut, step_value=127, label="Test 2b")


@cocotb.test()
async def test_step_response_negative(dut):
    """Test 2c: Negative Step Response - x[n] = -127 for all n.

    Verifies steady-state output equals sum(H) * (-127), exercising
    full-scale negative input to catch signed arithmetic issues.
    """
    await _run_step_test(dut, step_value=-127, label="Test 2c")


def test_fir_filter_dec2_runner():
    """Pytest runner for cocotb tests."""
    import os
    from pathlib import Path
    from cocotb_tools.runner import get_runner

    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path / "sources/fir_filter_dec2.v",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="fir_filter_dec2",
        always=True,
        waves=True
    )

    runner.test(
        hdl_toplevel="fir_filter_dec2",
        test_module="test_fir_filter_dec2_hidden",
        waves=True
    )


if __name__ == "__main__":
    test_fir_filter_dec2_runner()
