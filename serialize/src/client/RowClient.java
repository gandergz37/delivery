package client;

import protocol.RowProtocol;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Scanner;

/**
 * Cliente TCP: pede ao servidor o conteúdo de uma linha de qualquer tabela.
 *
 * <p>Uso direto:
 * <pre>
 *   java client.RowClient &lt;tabela&gt; &lt;colunaChave&gt; &lt;valor&gt; [host] [porta]
 *   java client.RowClient clientes id 2
 *   java client.RowClient produtos id 10 192.168.0.10 5555
 * </pre>
 *
 * <p>Sem argumentos, entra em modo interativo.
 */
public final class RowClient {

    private static final String DEFAULT_HOST = "127.0.0.1";
    private static final int DEFAULT_PORT = 5555;

    private RowClient() {
        // classe utilitária
    }

    public static void main(String[] args) throws IOException {
        if (args.length >= 3) {
            String host = args.length > 3 ? args[3] : DEFAULT_HOST;
            int port = args.length > 4 ? Integer.parseInt(args[4]) : DEFAULT_PORT;
            requestRow(host, port, args[0], args[1], args[2]);
        } else if (args.length == 0) {
            interactive(DEFAULT_HOST, DEFAULT_PORT);
        } else {
            System.out.println("Uso: java client.RowClient <tabela> <colunaChave> <valor> [host] [porta]");
        }
    }

    /**
     * Conecta, envia o pedido e imprime a linha recebida.
     */
    public static void requestRow(String host, int port,
                                  String table, String keyColumn, String keyValue) throws IOException {

        try (Socket socket = new Socket(host, port);
             DataOutputStream out = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));
             DataInputStream in = new DataInputStream(new BufferedInputStream(socket.getInputStream()))) {

            // 1) Envia a requisição
            RowProtocol.writeString(out, table);
            RowProtocol.writeString(out, keyColumn);
            RowProtocol.writeString(out, keyValue);
            out.flush();

            // 2) Lê a resposta
            byte status = in.readByte();
            switch (status) {
                case RowProtocol.STATUS_OK:
                    int columnCount = in.readInt();
                    Map<String, String> row = new LinkedHashMap<>();
                    for (int i = 0; i < columnCount; i++) {
                        String name = RowProtocol.readString(in);
                        String value = in.readBoolean() ? RowProtocol.readString(in) : null;
                        row.put(name, value);
                    }
                    System.out.println("Linha recebida de " + table + " (" + row.size() + " colunas):");
                    printRow(row);
                    break;

                case RowProtocol.STATUS_NOT_FOUND:
                    System.out.println("Nenhuma linha em '" + table + "' com "
                            + keyColumn + " = '" + keyValue + "'.");
                    break;

                case RowProtocol.STATUS_ERROR:
                    System.out.println("Erro retornado pelo servidor: " + RowProtocol.readString(in));
                    break;

                default:
                    System.out.println("Resposta desconhecida do servidor (status " + status + ").");
                    break;
            }
        }
    }

    private static void printRow(Map<String, String> row) {
        int width = 0;
        for (String name : row.keySet()) {
            width = Math.max(width, name.length());
        }
        for (Map.Entry<String, String> column : row.entrySet()) {
            String value = column.getValue() == null ? "NULL" : column.getValue();
            System.out.printf("  %-" + width + "s : %s%n", column.getKey(), value);
        }
    }

    private static void interactive(String host, int port) throws IOException {
        System.out.println("Servidor: " + host + ":" + port);
        try (Scanner scanner = new Scanner(System.in)) {
            while (true) {
                String table = ask(scanner, "Tabela (vazio para sair): ");
                if (table.isEmpty()) {
                    return;
                }
                String keyColumn = ask(scanner, "Coluna chave: ");
                String keyValue = ask(scanner, "Valor da chave: ");
                System.out.println();
                requestRow(host, port, table, keyColumn, keyValue);
                System.out.println();
            }
        }
    }

    private static String ask(Scanner scanner, String prompt) {
        System.out.print(prompt);
        if (!scanner.hasNextLine()) {
            return "";
        }
        return scanner.nextLine().trim();
    }
}
