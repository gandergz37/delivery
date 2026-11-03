package server;

import protocol.RowProtocol;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Servidor TCP multithread: aceita vários clientes e, para cada conexão, lê o pedido
 * (tabela, coluna-chave, valor) e chama {@link RowSender#sendRow}.
 *
 * <p>Uso: {@code java server.RowServer [porta] [caminhoDoBanco]}
 */
public final class RowServer {

    public static final int DEFAULT_PORT = 5555;
    public static final String DEFAULT_DATABASE = "db/demo.db";

    private final int port;
    private final String databasePath;
    private final SqliteRowRepository repository;
    private final ExecutorService clients = Executors.newCachedThreadPool();

    public RowServer(int port, String databasePath) {
        this.port = port;
        this.databasePath = databasePath;
        this.repository = new SqliteRowRepository(databasePath);
    }

    public void start() throws IOException {
        try (ServerSocket serverSocket = new ServerSocket(port)) {
            System.out.println("[servidor] ouvindo em 0.0.0.0:" + port);
            System.out.println("[servidor] banco de dados: " + databasePath);
            System.out.println("[servidor] Ctrl+C para encerrar");
            while (true) {
                Socket clientSocket = serverSocket.accept();
                clients.submit(() -> handle(clientSocket));
            }
        } finally {
            clients.shutdownNow();
        }
    }

    private void handle(Socket clientSocket) {
        String remote = String.valueOf(clientSocket.getRemoteSocketAddress());
        try (Socket socket = clientSocket;
             DataInputStream in = new DataInputStream(new BufferedInputStream(socket.getInputStream()))) {

            // Lê a requisição no formato definido em protocol.RowProtocol
            String table = RowProtocol.readString(in);
            String keyColumn = RowProtocol.readString(in);
            String keyValue = RowProtocol.readString(in);

            System.out.println("[servidor] " + remote + " pediu tabela=" + table
                    + " coluna=" + keyColumn + " valor=" + keyValue);

            // Função principal: envia a linha encontrada para o cliente
            RowSender.sendRow(socket, repository, table, keyColumn, keyValue);

        } catch (IOException e) {
            System.out.println("[servidor] erro de E/S com " + remote + ": " + e.getMessage());
        }
    }

    public static void main(String[] args) throws Exception {
        int port = args.length > 0 ? Integer.parseInt(args[0]) : DEFAULT_PORT;
        String databasePath = args.length > 1 ? args[1] : DEFAULT_DATABASE;

        if (!Files.exists(Path.of(databasePath))) {
            System.out.println("[servidor] banco nao encontrado, criando dados de exemplo em " + databasePath);
            DemoDatabase.create(databasePath);
        }

        new RowServer(port, databasePath).start();
    }
}
