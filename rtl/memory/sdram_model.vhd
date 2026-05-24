library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_model is
    generic (
        DATA_WIDTH    : positive := 32;
        ADDR_WIDTH    : positive := 18;
        READ_LATENCY  : natural  := 3;
        WRITE_LATENCY : natural  := 2;
        DEPTH         : positive := 262144
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        rd_req   : in std_logic;
        rd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_valid : out std_logic;
        rd_ready : out std_logic;

        wr_req   : in std_logic;
        wr_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        wr_data  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_ready : out std_logic;

        busy : out std_logic
    );
end entity sdram_model;

architecture sim of sdram_model is

    type ram_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    type state_t is (
        IDLE,
        READ_WAIT,
        WRITE_WAIT
    );

    signal ram : ram_t := (others => (others => '0'));

    signal state : state_t := IDLE;
    signal timer : natural := 0;

    signal pending_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal pending_data : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    signal rd_data_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal rd_valid_reg : std_logic := '0';
    signal rd_ready_reg : std_logic := '1';
    signal wr_ready_reg : std_logic := '1';
    signal busy_reg     : std_logic := '0';

begin

    rd_data  <= rd_data_reg;
    rd_valid <= rd_valid_reg;
    rd_ready <= rd_ready_reg;
    wr_ready <= wr_ready_reg;
    busy     <= busy_reg;

    assert not (rd_req = '1' and wr_req = '1')
        report "sdram_model aceita somente uma transacao por vez."
        severity warning;

    process(clk, rst)
        variable addr_int : integer;
    begin
        if rst = '1' then
            state        <= IDLE;
            timer        <= 0;
            pending_addr <= (others => '0');
            pending_data <= (others => '0');
            rd_data_reg  <= (others => '0');
            rd_valid_reg <= '0';
            rd_ready_reg <= '1';
            wr_ready_reg <= '1';
            busy_reg     <= '0';

        elsif rising_edge(clk) then
            rd_valid_reg <= '0';

            case state is
                when IDLE =>
                    rd_ready_reg <= '1';
                    wr_ready_reg <= '1';
                    busy_reg     <= '0';

                    if wr_req = '1' then
                        pending_addr <= wr_addr;
                        pending_data <= wr_data;
                        rd_ready_reg <= '0';
                        wr_ready_reg <= '0';
                        busy_reg     <= '1';

                        if WRITE_LATENCY = 0 then
                            addr_int := to_integer(wr_addr);

                            if addr_int < DEPTH then
                                ram(addr_int) <= wr_data;
                            end if;
                        else
                            timer <= WRITE_LATENCY;
                            state <= WRITE_WAIT;
                        end if;

                    elsif rd_req = '1' then
                        pending_addr <= rd_addr;
                        rd_ready_reg <= '0';
                        wr_ready_reg <= '0';
                        busy_reg     <= '1';

                        if READ_LATENCY = 0 then
                            addr_int := to_integer(rd_addr);

                            if addr_int < DEPTH then
                                rd_data_reg <= ram(addr_int);
                            else
                                rd_data_reg <= (others => '0');
                            end if;

                            rd_valid_reg <= '1';
                        else
                            timer <= READ_LATENCY;
                            state <= READ_WAIT;
                        end if;
                    end if;

                when READ_WAIT =>
                    rd_ready_reg <= '0';
                    wr_ready_reg <= '0';
                    busy_reg     <= '1';

                    if timer = 1 then
                        addr_int := to_integer(pending_addr);

                        if addr_int < DEPTH then
                            rd_data_reg <= ram(addr_int);
                        else
                            rd_data_reg <= (others => '0');
                        end if;

                        rd_valid_reg <= '1';
                        rd_ready_reg <= '1';
                        wr_ready_reg <= '1';
                        busy_reg     <= '0';
                        timer        <= 0;
                        state        <= IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                when WRITE_WAIT =>
                    rd_ready_reg <= '0';
                    wr_ready_reg <= '0';
                    busy_reg     <= '1';

                    if timer = 1 then
                        addr_int := to_integer(pending_addr);

                        if addr_int < DEPTH then
                            ram(addr_int) <= pending_data;
                        end if;

                        rd_ready_reg <= '1';
                        wr_ready_reg <= '1';
                        busy_reg     <= '0';
                        timer        <= 0;
                        state        <= IDLE;
                    else
                        timer <= timer - 1;
                    end if;
            end case;
        end if;
    end process;

end architecture sim;
