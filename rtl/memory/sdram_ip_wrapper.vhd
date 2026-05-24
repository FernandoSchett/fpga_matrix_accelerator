library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_ip_wrapper is
    generic (
        DATA_WIDTH    : positive := 32;
        ADDR_WIDTH    : positive := 18;
        READ_LATENCY  : natural  := 3;
        WRITE_LATENCY : natural  := 2
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
end entity sdram_ip_wrapper;

architecture rtl of sdram_ip_wrapper is

    -- Stub sintetizavel para a integracao futura com Platform Designer.
    --
    -- Quando o IP real de SDRAM for gerado, este arquivo deve continuar expondo
    -- somente a interface comum acima para o acelerador. Os sinais brutos do IP
    -- devem ficar encapsulados aqui.
    --
    -- Mapeamento previsto para um controlador Avalon-MM, se esse for o IP usado:
    --   rd_req        -> avm_read
    --   wr_req        -> avm_write
    --   rd_addr/wr_addr -> avm_address
    --   wr_data       -> avm_writedata
    --   rd_data       <- avm_readdata
    --   rd_valid      <- avm_readdatavalid, ou valid equivalente do IP
    --   rd_ready/wr_ready <- not avm_waitrequest, separado por politica local
    --   busy          <- transacao pendente ou waitrequest/estado interno
    --
    -- Ainda falta no Platform Designer:
    --   1. gerar o controlador SDRAM para a DE0-CV/Cyclone V;
    --   2. definir o clock/reset do controlador;
    --   3. exportar os pinos fisicos da SDRAM;
    --   4. escolher a largura/endereco usados pelo Avalon-MM;
    --   5. conectar os sinais Avalon-MM neste wrapper.
    --
    -- Para substituir o stub:
    --   1. mantenha esta entity e suas portas sem mudanca;
    --   2. instancie o componente gerado pelo Platform Designer nesta architecture;
    --   3. conecte rd_req/wr_req aos sinais de leitura/escrita do IP;
    --   4. gere rd_valid, rd_ready, wr_ready e busy a partir do handshake do IP.

    type state_t is (
        IDLE,
        READ_PENDING,
        WRITE_PENDING
    );

    signal state : state_t := IDLE;
    signal timer : natural := 0;

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

    process(clk, rst)
    begin
        if rst = '1' then
            state        <= IDLE;
            timer        <= 0;
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
                        rd_ready_reg <= '0';
                        wr_ready_reg <= '0';
                        busy_reg     <= '1';

                        if WRITE_LATENCY = 0 then
                            state <= IDLE;
                        else
                            timer <= WRITE_LATENCY;
                            state <= WRITE_PENDING;
                        end if;

                    elsif rd_req = '1' then
                        rd_ready_reg <= '0';
                        wr_ready_reg <= '0';
                        busy_reg     <= '1';

                        if READ_LATENCY = 0 then
                            rd_data_reg  <= (others => '0');
                            rd_valid_reg <= '1';
                            state        <= IDLE;
                        else
                            timer <= READ_LATENCY;
                            state <= READ_PENDING;
                        end if;
                    end if;

                when READ_PENDING =>
                    rd_ready_reg <= '0';
                    wr_ready_reg <= '0';
                    busy_reg     <= '1';

                    if timer = 1 then
                        rd_data_reg  <= (others => '0');
                        rd_valid_reg <= '1';
                        rd_ready_reg <= '1';
                        wr_ready_reg <= '1';
                        busy_reg     <= '0';
                        timer        <= 0;
                        state        <= IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                when WRITE_PENDING =>
                    rd_ready_reg <= '0';
                    wr_ready_reg <= '0';
                    busy_reg     <= '1';

                    if timer = 1 then
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

end architecture rtl;
