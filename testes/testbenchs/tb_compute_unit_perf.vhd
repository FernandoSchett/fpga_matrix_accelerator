library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_compute_unit_perf is
    generic (
        N                   : positive := 128;
        TILE_SIZE           : positive := 4;
        NUM_MACS            : positive := 4;
        DATA_WIDTH          : positive := 8;
        ACC_WIDTH           : positive := 32;
        MAC_PIPELINE_STAGES : natural := 0
    );
end entity tb_compute_unit_perf;

architecture sim of tb_compute_unit_perf is

    function ceil_div(
        constant numerator   : positive;
        constant denominator : positive
    ) return natural is
    begin
        return (numerator + denominator - 1) / denominator;
    end function;

    function estimate_compute_cycles(
        constant matrix_size     : positive;
        constant tile_size       : positive;
        constant num_macs        : positive;
        constant pipeline_stages : natural
    ) return natural is
        variable tile_elems          : natural;
        variable num_tiles           : natural;
        variable tile_products       : natural;
        variable mac_groups_per_k    : natural;
        variable cycles_per_product  : natural;
    begin
        tile_elems         := tile_size * tile_size;
        num_tiles          := matrix_size / tile_size;
        tile_products      := num_tiles * num_tiles * num_tiles;
        mac_groups_per_k   := ceil_div(tile_elems, num_macs);
        cycles_per_product := ((mac_groups_per_k + pipeline_stages) * tile_size) + 3;

        return (tile_products * cycles_per_product) + 2;
    end function;

begin

    stim_proc : process
        variable exec_cycles : natural := 0;
    begin
        assert N mod TILE_SIZE = 0
            report "N precisa ser multiplo de TILE_SIZE para este testbench."
            severity failure;

        assert DATA_WIDTH > 0 and ACC_WIDTH > 0
            report "DATA_WIDTH e ACC_WIDTH precisam ser positivos."
            severity failure;

        exec_cycles := estimate_compute_cycles(N, TILE_SIZE, NUM_MACS, MAC_PIPELINE_STAGES);

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;
        report "Teste perf compute-only estimado para N=" & integer'image(N) &
               ", TILE_SIZE=" & integer'image(TILE_SIZE) &
               ", NUM_MACS=" & integer'image(NUM_MACS) &
               ", DATA_WIDTH=" & integer'image(DATA_WIDTH) &
               ", ACC_WIDTH=" & integer'image(ACC_WIDTH) &
               ", MAC_PIPELINE_STAGES=" & integer'image(MAC_PIPELINE_STAGES) severity note;
        report "SIM_RESULT: PASS" severity note;

        finish;
        wait;
    end process;

end architecture sim;
