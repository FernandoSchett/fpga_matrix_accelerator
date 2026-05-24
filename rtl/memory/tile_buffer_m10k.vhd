library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tile_buffer_m10k is
    generic (
        ELEMENT_WIDTH  : positive := 8;
        ADDR_WIDTH     : positive := 4;
        DEPTH          : positive := 16;
        IMPLEMENTATION : string := "infer_m10k"
    );
    port (
        clk     : in std_logic;
        wr_en   : in std_logic;
        addr    : in unsigned(ADDR_WIDTH-1 downto 0);
        wr_data : in signed(ELEMENT_WIDTH-1 downto 0);
        rd_data : out signed(ELEMENT_WIDTH-1 downto 0)
    );
end entity tile_buffer_m10k;

architecture rtl of tile_buffer_m10k is
begin

    u_ram : entity work.matrix_single_port_ram
        generic map (
            DATA_WIDTH => ELEMENT_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => DEPTH
        )
        port map (
            clk     => clk,
            wr_en   => wr_en,
            addr    => addr,
            wr_data => wr_data,
            rd_data => rd_data
        );

end architecture rtl;
