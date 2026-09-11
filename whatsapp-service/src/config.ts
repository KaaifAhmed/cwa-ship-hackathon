import dotenv from "dotenv";

dotenv.config();

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

const port = Number(requiredEnv("PORT"));

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

export const config = {
  port,
  authDir: requiredEnv("AUTH_DIR"),
  mainServiceInboundUrl: requiredEnv("MAIN_SERVICE_INBOUND_URL"),
};
