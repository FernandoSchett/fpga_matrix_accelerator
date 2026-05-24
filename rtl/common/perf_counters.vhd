library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity perf_counters is
    generic (
        COUNTER_WIDTH : positive := 64
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start_count : in std_logic;
        stop_count  : in std_logic;

        load_active    : in std_logic;
        compute_active : in std_logic;
        store_active   : in std_logic;

        tile_done      : in std_logic;
        mac_ops_issued : in unsigned(COUNTER_WIDTH-1 downto 0);

        total_cycles          : out unsigned(COUNTER_WIDTH-1 downto 0);
        load_cycles           : out unsigned(COUNTER_WIDTH-1 downto 0);
        compute_cycles        : out unsigned(COUNTER_WIDTH-1 downto 0);
        store_cycles          : out unsigned(COUNTER_WIDTH-1 downto 0);
        num_tiles_processed   : out unsigned(COUNTER_WIDTH-1 downto 0);
        num_mac_ops_issued    : out unsigned(COUNTER_WIDTH-1 downto 0)
    );
end entity perf_counters;

architecture rtl of perf_counters is

    signal running_reg : std_logic := '0';

    signal total_cycles_reg        : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal load_cycles_reg         : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal compute_cycles_reg      : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal store_cycles_reg        : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal tiles_processed_reg     : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal mac_ops_issued_reg      : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');

begin

    total_cycles        <= total_cycles_reg;
    load_cycles         <= load_cycles_reg;
    compute_cycles      <= compute_cycles_reg;
    store_cycles        <= store_cycles_reg;
    num_tiles_processed <= tiles_processed_reg;
    num_mac_ops_issued  <= mac_ops_issued_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            running_reg          <= '0';
            total_cycles_reg     <= (others => '0');
            load_cycles_reg      <= (others => '0');
            compute_cycles_reg   <= (others => '0');
            store_cycles_reg     <= (others => '0');
            tiles_processed_reg  <= (others => '0');
            mac_ops_issued_reg   <= (others => '0');

        elsif rising_edge(clk) then
            if start_count = '1' then
                running_reg          <= '1';
                total_cycles_reg     <= (others => '0');
                load_cycles_reg      <= (others => '0');
                compute_cycles_reg   <= (others => '0');
                store_cycles_reg     <= (others => '0');
                tiles_processed_reg  <= (others => '0');
                mac_ops_issued_reg   <= (others => '0');
            else
                if running_reg = '1' then
                    total_cycles_reg <= total_cycles_reg + 1;

                    if load_active = '1' then
                        load_cycles_reg <= load_cycles_reg + 1;
                    end if;

                    if compute_active = '1' then
                        compute_cycles_reg <= compute_cycles_reg + 1;
                    end if;

                    if store_active = '1' then
                        store_cycles_reg <= store_cycles_reg + 1;
                    end if;

                    if tile_done = '1' then
                        tiles_processed_reg <= tiles_processed_reg + 1;
                    end if;

                    if mac_ops_issued /= 0 then
                        mac_ops_issued_reg <= mac_ops_issued_reg + mac_ops_issued;
                    end if;
                end if;

                if stop_count = '1' then
                    running_reg <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
