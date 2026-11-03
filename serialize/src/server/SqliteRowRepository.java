package server;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Acesso genérico ao banco SQLite: não conhece nenhuma tabela específica.
 *
 * <p>A tabela e a coluna-chave vêm como texto, então são validadas/escapadas antes de
 * entrar no SQL (identificadores não podem ser parametrizados com {@code ?}).
 * Já o valor da chave é sempre enviado como parâmetro, o que evita SQL Injection.
 */
public final class SqliteRowRepository {

    static {
        try {
            Class.forName("org.sqlite.JDBC");
        } catch (ClassNotFoundException e) {
            throw new IllegalStateException(
                    "Driver JDBC do SQLite não encontrado. Adicione sqlite-jdbc-*.jar ao classpath.", e);
        }
    }

    private final String jdbcUrl;

    public SqliteRowRepository(String databasePath) {
        if (databasePath == null || databasePath.isBlank()) {
            throw new IllegalArgumentException("Caminho do banco de dados vazio");
        }
        this.jdbcUrl = "jdbc:sqlite:" + databasePath;
    }

    /**
     * Busca UMA linha qualquer de uma tabela genérica.
     *
     * @param table     nome da tabela (qualquer tabela do banco)
     * @param keyColumn coluna usada na cláusula WHERE
     * @param keyValue  valor procurado nessa coluna
     * @return mapa ordenado coluna -> valor (o valor é {@code null} quando a coluna é NULL),
     *         ou {@code null} quando nenhuma linha corresponde
     */
    public Map<String, String> fetchRow(String table, String keyColumn, String keyValue) throws SQLException {
        String sql = "SELECT * FROM " + quoteIdentifier(table)
                + " WHERE " + quoteIdentifier(keyColumn) + " = ?"
                + " LIMIT 1";

        // Uma conexão por requisição: simples e seguro para vários clientes ao mesmo tempo.
        try (Connection connection = DriverManager.getConnection(jdbcUrl);
             PreparedStatement statement = connection.prepareStatement(sql)) {

            statement.setString(1, keyValue);

            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    return null;
                }
                ResultSetMetaData metaData = resultSet.getMetaData();
                int columnCount = metaData.getColumnCount();

                Map<String, String> row = new LinkedHashMap<>();
                for (int i = 1; i <= columnCount; i++) {
                    // getString devolve null quando a coluna é NULL
                    row.put(metaData.getColumnLabel(i), resultSet.getString(i));
                }
                return row;
            }
        }
    }

    /** Escapa um identificador (tabela/coluna) para uso seguro em SQL. */
    static String quoteIdentifier(String identifier) {
        if (identifier == null || identifier.isBlank()) {
            throw new IllegalArgumentException("Identificador de tabela/coluna vazio");
        }
        return '"' + identifier.replace("\"", "\"\"") + '"';
    }
}
