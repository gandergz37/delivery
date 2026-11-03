package server;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

/**
 * Cria o banco de exemplo (db/demo.db) com duas tabelas quaisquer, só para testar.
 * Nenhuma parte do servidor depende destas tabelas: qualquer tabela do banco funciona.
 */
public final class DemoDatabase {

    private DemoDatabase() {
        // classe utilitária
    }

    public static void create(String databasePath) throws Exception {
        Path path = Path.of(databasePath);
        Path parent = path.toAbsolutePath().getParent();
        if (parent != null) {
            Files.createDirectories(parent);
			
        }

        try (Connection connection = DriverManager.getConnection("jdbc:sqlite:" + databasePath);
             Statement statement = connection.createStatement()) {

            statement.executeUpdate("DROP TABLE IF EXISTS clientes");
            statement.executeUpdate("DROP TABLE IF EXISTS produtos");

            statement.executeUpdate("""
                    CREATE TABLE clientes (
                        id      INTEGER PRIMARY KEY,
                        nome    TEXT NOT NULL,
                        email   TEXT,
                        cidade  TEXT,
                        ativo   INTEGER
                    )""");

            statement.executeUpdate("""
                    CREATE TABLE produtos (
                        id       INTEGER PRIMARY KEY,
                        nome     TEXT NOT NULL,
                        preco    REAL,
                        estoque  INTEGER
                    )""");

            statement.executeUpdate("""
                    INSERT INTO clientes (id, nome, email, cidade, ativo) VALUES
                        (1, 'Ana Souza',    'ana@exemplo.com',    'São Paulo', 1),
                        (2, 'Bruno Lima',   'bruno@exemplo.com',  'Recife',    1),
                        (3, 'Carla Dias',   NULL,                 'Curitiba',  0),
                        (4, 'Diego Alves',  'diego@exemplo.com',  'Manaus',    1)""");

            statement.executeUpdate("""
                    INSERT INTO produtos (id, nome, preco, estoque) VALUES
                        (10, 'Teclado Mecânico', 349.90, 12),
                        (11, 'Mouse Sem Fio',     89.50, 40),
                        (12, 'Monitor 27"',     1299.00,  5)""");
        }

        System.out.println("[servidor] banco de exemplo criado: " + path.toAbsolutePath());
    }
}
