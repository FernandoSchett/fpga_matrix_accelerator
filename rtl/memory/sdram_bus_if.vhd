library ieee;
use ieee.std_logic_1164.all;

package sdram_bus_if_pkg is

    constant MATRIX_SEL_A : std_logic_vector(1 downto 0) := "00";
    constant MATRIX_SEL_B : std_logic_vector(1 downto 0) := "01";
    constant MATRIX_SEL_C : std_logic_vector(1 downto 0) := "10";

    constant SDRAM_CMD_READ  : std_logic := '0';
    constant SDRAM_CMD_WRITE : std_logic := '1';

end package sdram_bus_if_pkg;
