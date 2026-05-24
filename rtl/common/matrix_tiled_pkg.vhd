library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package matrix_tiled_pkg is

    function clog2(value : positive) return natural;
    function ceil_div(lhs : natural; rhs : positive) return natural;
    function row_major_addr(row_idx : natural; col_idx : natural; n : positive) return natural;

end package matrix_tiled_pkg;

package body matrix_tiled_pkg is

    function clog2(value : positive) return natural is
        variable result : natural := 0;
        variable limit  : natural := 1;
    begin
        while limit < value loop
            limit  := limit * 2;
            result := result + 1;
        end loop;

        return result;
    end function;

    function ceil_div(lhs : natural; rhs : positive) return natural is
    begin
        return (lhs + rhs - 1) / rhs;
    end function;

    function row_major_addr(row_idx : natural; col_idx : natural; n : positive) return natural is
    begin
        return (row_idx * n) + col_idx;
    end function;

end package body matrix_tiled_pkg;
