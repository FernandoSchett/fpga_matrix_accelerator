library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_ip_core is
    generic (
        ROW_WIDTH        : positive := 13;
        COL_WIDTH        : positive := 10;
        BANK_WIDTH       : positive := 2;
        CLK_FREQUENCY    : positive := 50;
        REFRESH_TIME_MS  : positive := 64;
        REFRESH_COUNT    : positive := 8192
    );
    port (
        clk            : in std_logic;
        reset_n        : in std_logic;

        az_addr        : in std_logic_vector((ROW_WIDTH + COL_WIDTH + BANK_WIDTH)-1 downto 0);
        az_be_n        : in std_logic_vector(1 downto 0);
        az_cs          : in std_logic;
        az_data        : in std_logic_vector(15 downto 0);
        az_rd_n        : in std_logic;
        az_wr_n        : in std_logic;
        za_data        : out std_logic_vector(15 downto 0);
        za_valid       : out std_logic;
        za_waitrequest : out std_logic;

        zs_addr        : out std_logic_vector(ROW_WIDTH-1 downto 0);
        zs_ba          : out std_logic_vector(BANK_WIDTH-1 downto 0);
        zs_cas_n       : out std_logic;
        zs_cke         : out std_logic;
        zs_cs_n        : out std_logic;
        zs_dq          : inout std_logic_vector(15 downto 0);
        zs_dqm         : out std_logic_vector(1 downto 0);
        zs_ras_n       : out std_logic;
        zs_we_n        : out std_logic
    );
end entity sdram_ip_core;

architecture rtl of sdram_ip_core is

    constant HADDR_WIDTH : positive := BANK_WIDTH + ROW_WIDTH + COL_WIDTH;

    component sdram_controller is
        generic (
            ROW_WIDTH     : integer := 13;
            COL_WIDTH     : integer := 10;
            BANK_WIDTH    : integer := 2;
            SDRADDR_WIDTH : integer := 13;
            HADDR_WIDTH   : integer := 25;
            CLK_FREQUENCY : integer := 50;
            REFRESH_TIME  : integer := 64;
            REFRESH_COUNT : integer := 8192
        );
        port (
            wr_addr        : in std_logic_vector(HADDR_WIDTH-1 downto 0);
            wr_data        : in std_logic_vector(15 downto 0);
            wr_enable      : in std_logic;
            rd_addr        : in std_logic_vector(HADDR_WIDTH-1 downto 0);
            rd_data        : out std_logic_vector(15 downto 0);
            rd_ready       : out std_logic;
            rd_enable      : in std_logic;
            busy           : out std_logic;
            rst_n          : in std_logic;
            clk            : in std_logic;
            addr           : out std_logic_vector(ROW_WIDTH-1 downto 0);
            bank_addr      : out std_logic_vector(BANK_WIDTH-1 downto 0);
            data           : inout std_logic_vector(15 downto 0);
            clock_enable   : out std_logic;
            cs_n           : out std_logic;
            ras_n          : out std_logic;
            cas_n          : out std_logic;
            we_n           : out std_logic;
            data_mask_low  : out std_logic;
            data_mask_high : out std_logic
        );
    end component;

    signal core_busy      : std_logic;
    signal core_rd_ready  : std_logic;
    signal core_rd_data   : std_logic_vector(15 downto 0);
    signal core_wr_enable : std_logic;
    signal core_rd_enable : std_logic;
    signal data_mask_low  : std_logic;
    signal data_mask_high : std_logic;

begin

    core_wr_enable <= '1' when az_cs = '1' and az_wr_n = '0' and core_busy = '0' else '0';
    core_rd_enable <= '1' when az_cs = '1' and az_rd_n = '0' and core_busy = '0' else '0';

    za_waitrequest <= core_busy;
    za_valid       <= core_rd_ready;
    za_data        <= core_rd_data;
    zs_dqm(0)      <= data_mask_low or az_be_n(0);
    zs_dqm(1)      <= data_mask_high or az_be_n(1);

    u_vendor_sdram : sdram_controller
        generic map (
            ROW_WIDTH     => ROW_WIDTH,
            COL_WIDTH     => COL_WIDTH,
            BANK_WIDTH    => BANK_WIDTH,
            SDRADDR_WIDTH => ROW_WIDTH,
            HADDR_WIDTH   => HADDR_WIDTH,
            CLK_FREQUENCY => CLK_FREQUENCY,
            REFRESH_TIME  => REFRESH_TIME_MS,
            REFRESH_COUNT => REFRESH_COUNT
        )
        port map (
            wr_addr        => az_addr,
            wr_data        => az_data,
            wr_enable      => core_wr_enable,
            rd_addr        => az_addr,
            rd_data        => core_rd_data,
            rd_ready       => core_rd_ready,
            rd_enable      => core_rd_enable,
            busy           => core_busy,
            rst_n          => reset_n,
            clk            => clk,
            addr           => zs_addr,
            bank_addr      => zs_ba,
            data           => zs_dq,
            clock_enable   => zs_cke,
            cs_n           => zs_cs_n,
            ras_n          => zs_ras_n,
            cas_n          => zs_cas_n,
            we_n           => zs_we_n,
            data_mask_low  => data_mask_low,
            data_mask_high => data_mask_high
        );

end architecture rtl;
