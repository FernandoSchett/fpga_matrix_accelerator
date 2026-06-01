library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller_wrapper is
    generic (
        ADDR_WIDTH : positive := 25;
        DATA_WIDTH : positive := 32
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        cmd_valid : in std_logic;
        cmd_write : in std_logic;
        cmd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        cmd_wdata : in std_logic_vector(DATA_WIDTH-1 downto 0);
        cmd_be    : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        cmd_ready : out std_logic;

        rd_valid : out std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        busy     : out std_logic
    );
end entity sdram_controller_wrapper;

architecture stub of sdram_controller_wrapper is
begin

    -- Stub sintetizavel. Trocar por IP SDRAM/Platform Designer.
    -- Mantem acelerador dependente de barramento simples, nao dos sinais crus da SDRAM.
    cmd_ready <= '1';
    rd_valid  <= '0';
    rd_data   <= (others => '0');
    busy      <= cmd_valid and not cmd_write;

end architecture stub;
