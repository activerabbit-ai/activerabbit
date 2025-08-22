-- Initialize PostgreSQL database for ActiveRabbit
-- This script runs when the database container starts for the first time

-- Create the development database if it doesn't exist
SELECT 'CREATE DATABASE activerabbit_development'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'activerabbit_development')\gexec

-- Create the test database if it doesn't exist
SELECT 'CREATE DATABASE activerabbit_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'activerabbit_test')\gexec
