library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sdram_bus_if_pkg.all;

package matrix_memory_map_pkg is

    function matrix_elem_bytes(width_bits : positive) return positive;

    function selected_matrix_base(
        configured_base : natural;
        default_base    : natural
    ) return natural;

    function matrix_base_b(
        n            : positive;
        data_width   : positive;
        base_a_bytes : natural;
        base_b_bytes : natural
    ) return natural;

    function matrix_base_c(
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural
    ) return natural;

    function matrix_linear_byte_addr(
        matrix_sel   : std_logic_vector(1 downto 0);
        linear_index : natural;
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural;
        addr_width   : positive
    ) return unsigned;

    function matrix_byte_addr(
        matrix_sel   : std_logic_vector(1 downto 0);
        row_idx      : natural;
        col_idx      : natural;
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural;
        addr_width   : positive
    ) return unsigned;

end package matrix_memory_map_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sdram_bus_if_pkg.all;

package body matrix_memory_map_pkg is

    function matrix_elem_bytes(width_bits : positive) return positive is
    begin
        return (width_bits + 7) / 8;
    end function;

    function selected_matrix_base(
        configured_base : natural;
        default_base    : natural
    ) return natural is
    begin
        if configured_base = 0 then
            return default_base;
        end if;
        return configured_base;
    end function;

    function matrix_base_b(
        n            : positive;
        data_width   : positive;
        base_a_bytes : natural;
        base_b_bytes : natural
    ) return natural is
        variable matrix_elems : natural;
        variable a_bytes      : natural;
    begin
        matrix_elems := n * n;
        a_bytes := matrix_elems * matrix_elem_bytes(data_width);
        return selected_matrix_base(base_b_bytes, base_a_bytes + a_bytes);
    end function;

    function matrix_base_c(
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural
    ) return natural is
        variable matrix_elems : natural;
        variable b_base       : natural;
        variable b_bytes      : natural;
    begin
        matrix_elems := n * n;
        b_base := matrix_base_b(n, data_width, base_a_bytes, base_b_bytes);
        b_bytes := matrix_elems * matrix_elem_bytes(data_width);
        return selected_matrix_base(base_c_bytes, b_base + b_bytes);
    end function;

    function matrix_linear_byte_addr(
        matrix_sel   : std_logic_vector(1 downto 0);
        linear_index : natural;
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural;
        addr_width   : positive
    ) return unsigned is
        variable byte_addr : natural;
    begin
        byte_addr := base_a_bytes + (linear_index * matrix_elem_bytes(data_width));

        if matrix_sel = MATRIX_SEL_B then
            byte_addr := matrix_base_b(n, data_width, base_a_bytes, base_b_bytes) +
                         (linear_index * matrix_elem_bytes(data_width));
        elsif matrix_sel = MATRIX_SEL_C then
            byte_addr := matrix_base_c(n, data_width, acc_width, base_a_bytes, base_b_bytes, base_c_bytes) +
                         (linear_index * matrix_elem_bytes(acc_width));
        end if;

        return to_unsigned(byte_addr, addr_width);
    end function;

    function matrix_byte_addr(
        matrix_sel   : std_logic_vector(1 downto 0);
        row_idx      : natural;
        col_idx      : natural;
        n            : positive;
        data_width   : positive;
        acc_width    : positive;
        base_a_bytes : natural;
        base_b_bytes : natural;
        base_c_bytes : natural;
        addr_width   : positive
    ) return unsigned is
        variable linear_index : natural;
    begin
        linear_index := (row_idx * n) + col_idx;
        return matrix_linear_byte_addr(matrix_sel, linear_index, n, data_width, acc_width,
                                       base_a_bytes, base_b_bytes, base_c_bytes, addr_width);
    end function;

end package body matrix_memory_map_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.sdram_bus_if_pkg.all;
use work.matrix_memory_map_pkg.all;

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
begin

    process(matrix_sel, row_idx, col_idx)
    begin
        valid <= '1';
        if matrix_sel /= MATRIX_SEL_A and matrix_sel /= MATRIX_SEL_B and matrix_sel /= MATRIX_SEL_C then
            valid <= '0';
        end if;

        byte_addr <= matrix_byte_addr(matrix_sel,
                                      to_integer(row_idx),
                                      to_integer(col_idx),
                                      N,
                                      DATA_WIDTH,
                                      ACC_WIDTH,
                                      BASE_A_BYTES,
                                      BASE_B_BYTES,
                                      BASE_C_BYTES,
                                      ADDR_WIDTH);
    end process;

end architecture rtl;
