library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.matrix_accel_config_pkg.all;

entity matrix_memory_map is
    generic (
        N          : positive := DEFAULT_N;
        ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH
    );
    port (
        matrix_id : in std_logic_vector(1 downto 0);
        row_idx   : in unsigned(clog2(N)-1 downto 0);
        col_idx   : in unsigned(clog2(N)-1 downto 0);
        addr      : out unsigned(ADDR_WIDTH-1 downto 0)
    );
end entity matrix_memory_map;

architecture rtl of matrix_memory_map is

    constant MATRIX_ELEMS : natural := N * N;
    constant A_BASE       : natural := 0;
    constant B_BASE       : natural := MATRIX_ELEMS;
    constant C_BASE       : natural := MATRIX_ELEMS * 2;

begin

    process(matrix_id, row_idx, col_idx)
        variable base        : natural;
        variable element_idx : natural;
    begin
        if matrix_id = MATRIX_ID_A then
            base := A_BASE;
        elsif matrix_id = MATRIX_ID_B then
            base := B_BASE;
        else
            base := C_BASE;
        end if;

        element_idx := row_major_addr(to_integer(row_idx), to_integer(col_idx), N);
        addr <= to_unsigned(base + element_idx, ADDR_WIDTH);
    end process;

end architecture rtl;
