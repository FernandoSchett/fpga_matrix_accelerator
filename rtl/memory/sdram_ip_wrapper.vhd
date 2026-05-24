library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_ip_wrapper is
    generic (
        DATA_WIDTH : positive := 32;
        ADDR_WIDTH : positive := 18
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        req     : in std_logic;
        we      : in std_logic;
        addr    : in unsigned(ADDR_WIDTH-1 downto 0);
        wdata   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        byte_en : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);

        ready  : out std_logic;
        rvalid : out std_logic;
        rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity sdram_ip_wrapper;

architecture rtl of sdram_ip_wrapper is

    signal rvalid_reg : std_logic := '0';

begin

    ready  <= '1';
    rvalid <= rvalid_reg;
    rdata  <= (others => '0');

    process(clk, rst)
    begin
        if rst = '1' then
            rvalid_reg <= '0';
        elsif rising_edge(clk) then
            rvalid_reg <= req and not we;
        end if;
    end process;

end architecture rtl;
