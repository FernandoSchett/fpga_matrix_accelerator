library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity tb_matrix_memory_map is
end entity tb_matrix_memory_map;

architecture sim of tb_matrix_memory_map is

    constant N          : positive := 4;
    constant ADDR_WIDTH : positive := 8;

    signal matrix_id : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal row_idx   : unsigned(1 downto 0) := (others => '0');
    signal col_idx   : unsigned(1 downto 0) := (others => '0');
    signal addr      : unsigned(ADDR_WIDTH-1 downto 0);

begin

    dut : entity work.matrix_memory_map
        generic map (
            N          => N,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            matrix_id => matrix_id,
            row_idx   => row_idx,
            col_idx   => col_idx,
            addr      => addr
        );

    stim_proc : process
    begin
        row_idx <= to_unsigned(1, row_idx'length);
        col_idx <= to_unsigned(2, col_idx'length);

        matrix_id <= MATRIX_ID_A;
        wait for 1 ns;
        assert addr = to_unsigned(6, ADDR_WIDTH)
            report "Endereco de A incorreto."
            severity failure;

        matrix_id <= MATRIX_ID_B;
        wait for 1 ns;
        assert addr = to_unsigned(22, ADDR_WIDTH)
            report "Endereco de B incorreto."
            severity failure;

        matrix_id <= MATRIX_ID_C;
        wait for 1 ns;
        assert addr = to_unsigned(38, ADDR_WIDTH)
            report "Endereco de C incorreto."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
