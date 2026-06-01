library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.sdram_bus_if_pkg.all;

entity matrix_memory_map is
    generic (
        N            : positive := 512;
        DATA_WIDTH   : positive := 8;
        ACC_WIDTH    : positive := 32;
        ADDR_WIDTH   : positive := 25;
        BASE_A_BYTES : natural := 0;
        BASE_B_BYTES : natural := 0;
        BASE_C_BYTES : natural := 0
    );
    port (
        matrix_sel : in  std_logic_vector(1 downto 0);
        row_idx    : in  unsigned(clog2(N)-1 downto 0);
        col_idx    : in  unsigned(clog2(N)-1 downto 0);
        byte_addr  : out unsigned(ADDR_WIDTH-1 downto 0);
        valid      : out std_logic
    );
end entity matrix_memory_map;

architecture rtl of matrix_memory_map is

    function select_base(configured_base : natural; default_base : natural) return natural is
    begin
        if configured_base = 0 then
            return default_base;
        end if;
        return configured_base;
    end function;

    constant DATA_BYTES       : positive := (DATA_WIDTH + 7) / 8;
    constant ACC_BYTES        : positive := (ACC_WIDTH + 7) / 8;
    constant MATRIX_ELEMS     : natural := N * N;
    constant A_BYTES          : natural := MATRIX_ELEMS * DATA_BYTES;
    constant B_BYTES          : natural := MATRIX_ELEMS * DATA_BYTES;
    constant DEFAULT_BASE_B   : natural := BASE_A_BYTES + A_BYTES;
    constant SELECTED_BASE_B  : natural := select_base(BASE_B_BYTES, DEFAULT_BASE_B);
    constant DEFAULT_BASE_C   : natural := SELECTED_BASE_B + B_BYTES;
    constant SELECTED_BASE_C  : natural := select_base(BASE_C_BYTES, DEFAULT_BASE_C);

begin

    process(matrix_sel, row_idx, col_idx)
        variable linear_index : natural;
        variable addr_value   : natural;
    begin
        linear_index := to_integer(row_idx) * N + to_integer(col_idx);
        addr_value   := BASE_A_BYTES;
        valid        <= '1';

        case matrix_sel is
            when MATRIX_SEL_A =>
                addr_value := BASE_A_BYTES + (linear_index * DATA_BYTES);

            when MATRIX_SEL_B =>
                addr_value := SELECTED_BASE_B + (linear_index * DATA_BYTES);

            when MATRIX_SEL_C =>
                addr_value := SELECTED_BASE_C + (linear_index * ACC_BYTES);

            when others =>
                addr_value := 0;
                valid      <= '0';
        end case;

        byte_addr <= to_unsigned(addr_value, ADDR_WIDTH);
    end process;

end architecture rtl;
