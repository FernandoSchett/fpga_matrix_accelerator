library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_mult_top is
    generic (
        DATA_WIDTH : integer := 16;
        ACC_WIDTH  : integer := 32
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;

        wr_en      : in std_logic;
        matrix_sel : in std_logic; -- '0' = A, '1' = B
        wr_addr    : in unsigned(1 downto 0);
        data_in    : in signed(DATA_WIDTH-1 downto 0);

        cin_wr_en   : in std_logic;
        cin_addr    : in unsigned(1 downto 0);
        cin_data_in : in signed(ACC_WIDTH-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        result_sel : in unsigned(1 downto 0);
        data_out   : out signed(ACC_WIDTH-1 downto 0)
    );
end entity matrix_mult_top;

architecture rtl of matrix_mult_top is

    type state_t is (
        IDLE,
        RUN,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal a00_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a01_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a10_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a11_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal b00_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b01_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b10_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b11_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal c00_in_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c01_in_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c10_in_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c11_in_reg : signed(ACC_WIDTH-1 downto 0) := (others => '0');

    signal c00_wire : signed(ACC_WIDTH-1 downto 0);
    signal c01_wire : signed(ACC_WIDTH-1 downto 0);
    signal c10_wire : signed(ACC_WIDTH-1 downto 0);
    signal c11_wire : signed(ACC_WIDTH-1 downto 0);

    signal core_start : std_logic := '0';
    signal core_done  : std_logic;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

begin

    busy <= busy_reg;
    done <= done_reg;

    with result_sel select
        data_out <= c00_wire when "00",
                    c01_wire when "01",
                    c10_wire when "10",
                    c11_wire when others;

    u_core : entity work.matrix_mult_core
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk   => clk,
            rst   => rst,
            start => core_start,
            done  => core_done,

            a00 => a00_reg,
            a01 => a01_reg,
            a10 => a10_reg,
            a11 => a11_reg,

            b00 => b00_reg,
            b01 => b01_reg,
            b10 => b10_reg,
            b11 => b11_reg,

            c00_in => c00_in_reg,
            c01_in => c01_in_reg,
            c10_in => c10_in_reg,
            c11_in => c11_in_reg,

            c00 => c00_wire,
            c01 => c01_wire,
            c10 => c10_wire,
            c11 => c11_wire
        );

    process(clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;

            a00_reg <= (others => '0');
            a01_reg <= (others => '0');
            a10_reg <= (others => '0');
            a11_reg <= (others => '0');

            b00_reg <= (others => '0');
            b01_reg <= (others => '0');
            b10_reg <= (others => '0');
            b11_reg <= (others => '0');

            c00_in_reg <= (others => '0');
            c01_in_reg <= (others => '0');
            c10_in_reg <= (others => '0');
            c11_in_reg <= (others => '0');

            core_start <= '0';
            busy_reg   <= '0';
            done_reg   <= '0';

        elsif rising_edge(clk) then

            core_start <= '0';

            case state is

                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if wr_en = '1' then
                        if matrix_sel = '0' then
                            case wr_addr is
                                when "00" =>
                                    a00_reg <= data_in;
                                when "01" =>
                                    a01_reg <= data_in;
                                when "10" =>
                                    a10_reg <= data_in;
                                when others =>
                                    a11_reg <= data_in;
                            end case;
                        else
                            case wr_addr is
                                when "00" =>
                                    b00_reg <= data_in;
                                when "01" =>
                                    b01_reg <= data_in;
                                when "10" =>
                                    b10_reg <= data_in;
                                when others =>
                                    b11_reg <= data_in;
                            end case;
                        end if;
                    end if;

                    if cin_wr_en = '1' then
                        case cin_addr is
                            when "00" =>
                                c00_in_reg <= cin_data_in;
                            when "01" =>
                                c01_in_reg <= cin_data_in;
                            when "10" =>
                                c10_in_reg <= cin_data_in;
                            when others =>
                                c11_in_reg <= cin_data_in;
                        end case;
                    end if;

                    if start = '1' then
                        core_start <= '1';
                        busy_reg   <= '1';
                        state      <= RUN;
                    end if;

                when RUN =>
                    busy_reg <= '1';
                    done_reg <= '0';

                    if core_done = '1' then
                        busy_reg <= '0';
                        done_reg <= '1';
                        state    <= DONE_STATE;
                    end if;

                when DONE_STATE =>
                    busy_reg <= '0';
                    done_reg <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;

            end case;

        end if;
    end process;

end architecture rtl;