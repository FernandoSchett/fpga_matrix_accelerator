library ieee;
use ieee.std_logic_1164.all;

package matrix_accel_config_pkg is

    constant DEFAULT_N          : positive := 128;
    constant DEFAULT_TILE_SIZE  : positive := 4;
    constant DEFAULT_NUM_MACS   : positive := 4;
    constant DEFAULT_DATA_WIDTH : positive := 8;
    constant DEFAULT_ACC_WIDTH  : positive := 32;
    constant DEFAULT_HOST_DATA_WIDTH : positive := 32;
    constant DEFAULT_ADDR_WIDTH      : positive := 14; -- clog2(128*128)

    constant MATRIX_ID_A : std_logic_vector(1 downto 0) := "00";
    constant MATRIX_ID_B : std_logic_vector(1 downto 0) := "01";
    constant MATRIX_ID_C : std_logic_vector(1 downto 0) := "10";

end package matrix_accel_config_pkg;
