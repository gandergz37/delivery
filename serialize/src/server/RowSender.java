package server;

import protocol.RowProtocol;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.sql.SQLException;
import java.util.Map;

/**
 * AQUI ESTÁ A FUNÇÃO PEDIDA.
 *
 * <p>{@link #sendRow(Socket, SqliteRowRepository, String, String, String)} recebe um socket
 * já conectado ao cliente e envia o conteúdo de uma linha qualquer de uma tabela genérica
 * do banco SQLite. Nada na função conhece o esquema: as colunas e os valores são descobertos
 * em tempo de execução pelo {@link java.sql.ResultSetMetaData}.
 */
public final class RowSender {

    private RowSender() {
        // classe utilitária
    }

    /**
     * Envia para o cliente a linha de {@code table} cujo {@code keyColumn} é igual a
     * {@code keyValue}.
     *
     * @param socket     conexão já aceita pelo servidor (o servidor fecha depois)
     * @param repository acesso ao banco SQLite
     * @param table      nome da tabela (qualquer tabela do banco)
     * @param keyColumn  coluna usada para localizar a linha
     * @param keyValue   valor procurado nessa coluna
     */
    public static void sendRow(Socket socket,
                               SqliteRowRepository repository,
                               String table,
                               String keyColumn,
                               String keyValue) throws IOException {

        DataOutputStream out = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));

        Map<String, String> row;
        try {
            // 1) Busca a linha antes de escrever qualquer byte: se falhar, o cliente
            //    recebe apenas uma resposta de erro consistente.
            row = repository.fetchRow(table, keyColumn, keyValue);
        } catch (SQLException | IllegalArgumentException e) {
            writeError(out, e.getMessage());
            return;
        }

        // 2) Linha não encontrada
        if (row == null) {
            out.writeByte(RowProtocol.STATUS_NOT_FOUND);
            out.flush();
            return;
        }

        // 3) Linha encontrada: envia nome da coluna + valor (ou NULL) de cada coluna
        out.writeByte(RowProtocol.STATUS_OK);
        out.writeInt(row.size());
        for (Map.Entry<String, String> column : row.entrySet()) {
            RowProtocol.writeString(out, column.getKey());
            boolean notNull = column.getValue() != null;
            out.writeBoolean(notNull);
            if (notNull) {
                RowProtocol.writeString(out, column.getValue());
            }
        }
        out.flush();
    }

    /**
     * Atalho para quem só tem o caminho do banco de dados.
     */
    public static void sendRow(Socket socket,
                               String databasePath,
                               String table,
                               String keyColumn,
                               String keyValue) throws IOException {
        sendRow(socket, new SqliteRowRepository(databasePath), table, keyColumn, keyValue);
    }

    private static void writeError(DataOutputStream out, String message) throws IOException {
        out.writeByte(RowProtocol.STATUS_ERROR);
        RowProtocol.writeString(out, message == null ? "Erro desconhecido no servidor" : message);
        out.flush();
    }
}
