package com.delivery.serialize;

import java.io.DataOutputStream;
import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

public class GenericRowServer {
    private static final int PORT = 12345;
    private final String dbUrl;
    
    public GenericRowServer(String dbUrl) {
        this.dbUrl = dbUrl;
    }
    
    public void start() {
        try (ServerSocket serverSocket = new ServerSocket(PORT)) {
            System.out.println("Servidor aguardando conexao na porta " + PORT);
            System.out.println("Banco de dados: " + dbUrl);
            
            while (true) {
                Socket clientSocket = serverSocket.accept();
                System.out.println("Cliente conectado: " + clientSocket.getInetAddress());
                
                new Thread(() -> handleClient(clientSocket)).start();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
    
    private void handleClient(Socket clientSocket) {
        try (Socket socket = clientSocket;
             Connection conn = DriverManager.getConnection(dbUrl);
             DataOutputStream out = new DataOutputStream(socket.getOutputStream())) {
            
            Statement stmt = conn.createStatement();
            // Query genérica - exemplo: primeira linha da tabela orders
            // Para ser genérico, podemos buscar por nome da tabela e id via parâmetros
            String query = "SELECT * FROM orders LIMIT 1";
            System.out.println("Executando: " + query);
            
            ResultSet rs = stmt.executeQuery(query);
            if (rs.next()) {
                RowSerializer.serializeRow(rs, out);
                System.out.println("Linha enviada com sucesso");
            } else {
                System.out.println("Nenhum registro encontrado");
            }
            
        } catch (SQLException | IOException e) {
            e.printStackTrace();
        }
    }
    
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Uso: java GenericRowServer <jdbc:sqlite:caminho/banco.db>");
            System.out.println("Exemplo: java GenericRowServer jdbc:sqlite:C:/Users/gandergz/delivery.db");
            System.exit(1);
        }
        
        new GenericRowServer(args[0]).start();
    }
}
