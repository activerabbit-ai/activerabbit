-- Initialize PostgreSQL database for ActiveAgent
-- This script runs when the database container starts for the first time

-- Create the development database if it doesn't exist
SELECT 'CREATE DATABASE activeagent_development'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'activeagent_development')\gexec

-- Create the test database if it doesn't exist
SELECT 'CREATE DATABASE activeagent_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'activeagent_test')\gexec
