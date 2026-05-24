library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_bus_if is
    generic (
        DATA_WIDTH : positive := 32;
        ADDR_WIDTH : positive := 18
    );
    port (
        client_req     : in std_logic;
        client_we      : in std_logic;
        client_addr    : in unsigned(ADDR_WIDTH-1 downto 0);
        client_wdata   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        client_byte_en : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        client_ready   : out std_logic;
        client_rvalid  : out std_logic;
        client_rdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);

        mem_req     : out std_logic;
        mem_we      : out std_logic;
        mem_addr    : out unsigned(ADDR_WIDTH-1 downto 0);
        mem_wdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_byte_en : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        mem_ready   : in std_logic;
        mem_rvalid  : in std_logic;
        mem_rdata   : in std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity sdram_bus_if;

architecture rtl of sdram_bus_if is
begin

    mem_req     <= client_req;
    mem_we      <= client_we;
    mem_addr    <= client_addr;
    mem_wdata   <= client_wdata;
    mem_byte_en <= client_byte_en;

    client_ready  <= mem_ready;
    client_rvalid <= mem_rvalid;
    client_rdata  <= mem_rdata;

end architecture rtl;
