library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity tb_matrix_memory_map is
end entity tb_matrix_memory_map;

architecture sim of tb_matrix_memory_map is

    constant DATA_WIDTH : positive := 8;
    constant ACC_WIDTH  : positive := 32;

    constant N4          : positive := 4;
    constant ADDR_WIDTH4 : positive := 8;
    constant BASE_A4     : natural := 0;
    constant BASE_B4     : natural := N4 * N4;
    constant BASE_C4     : natural := 2 * N4 * N4;

    constant N128          : positive := 128;
    constant ADDR_WIDTH128 : positive := 18;
    constant BASE_A128     : natural := 0;
    constant BASE_B128     : natural := N128 * N128;
    constant BASE_C128     : natural := 2 * N128 * N128;

    signal matrix_id4 : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal row_idx4   : unsigned(1 downto 0) := (others => '0');
    signal col_idx4   : unsigned(1 downto 0) := (others => '0');
    signal addr4      : unsigned(ADDR_WIDTH4-1 downto 0);

    signal matrix_id128 : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal row_idx128   : unsigned(6 downto 0) := (others => '0');
    signal col_idx128   : unsigned(6 downto 0) := (others => '0');
    signal addr128      : unsigned(ADDR_WIDTH128-1 downto 0);

    procedure check_addr(
        signal matrix_id : out std_logic_vector(1 downto 0);
        signal row_idx   : out unsigned;
        signal col_idx   : out unsigned;
        signal addr      : in unsigned;
        constant sel     : in std_logic_vector(1 downto 0);
        constant row_v   : in natural;
        constant col_v   : in natural;
        constant expected : in natural;
        constant label_s  : in string
    ) is
    begin
        matrix_id <= sel;
        row_idx   <= to_unsigned(row_v, row_idx'length);
        col_idx   <= to_unsigned(col_v, col_idx'length);
        wait for 1 ns;

        assert addr = to_unsigned(expected, addr'length)
            report label_s & " incorreto. Esperado " & integer'image(expected) &
                   ", obtido " & integer'image(to_integer(addr))
            severity failure;
    end procedure;

begin

    dut_n4 : entity work.matrix_memory_map
        generic map (
            N          => N4,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH4
        )
        port map (
            matrix_id => matrix_id4,
            row_idx   => row_idx4,
            col_idx   => col_idx4,
            addr      => addr4
        );

    dut_n128 : entity work.matrix_memory_map
        generic map (
            N          => N128,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH128
        )
        port map (
            matrix_id => matrix_id128,
            row_idx   => row_idx128,
            col_idx   => col_idx128,
            addr      => addr128
        );

    stim_proc : process
    begin
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_A, 0, 0, BASE_A4 + 0, "N=4 A[0][0]");
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_A, 0, 1, BASE_A4 + 1, "N=4 A[0][1]");
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_A, 1, 0, BASE_A4 + N4, "N=4 A[1][0]");
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_B, 0, 0, BASE_B4 + 0, "N=4 B[0][0]");
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_C, 0, 0, BASE_C4 + 0, "N=4 C[0][0]");
        check_addr(matrix_id4, row_idx4, col_idx4, addr4,
                   MATRIX_ID_C, 1, 0, BASE_C4 + N4, "N=4 C[1][0]");

        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_A, 0, 0, BASE_A128 + 0, "N=128 A[0][0]");
        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_A, 0, 1, BASE_A128 + 1, "N=128 A[0][1]");
        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_A, 1, 0, BASE_A128 + N128, "N=128 A[1][0]");
        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_B, 0, 0, BASE_B128 + 0, "N=128 B[0][0]");
        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_C, 0, 0, BASE_C128 + 0, "N=128 C[0][0]");
        check_addr(matrix_id128, row_idx128, col_idx128, addr128,
                   MATRIX_ID_C, 1, 0, BASE_C128 + N128, "N=128 C[1][0]");

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
