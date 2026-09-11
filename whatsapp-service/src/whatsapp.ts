import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
  WASocket,
} from "@whiskeysockets/baileys";
import { Boom } from "@hapi/boom";
import qrcode from "qrcode-terminal";
import pino from "pino";
import axios from "axios";
import fs from "fs";

import { config } from "./config.js";

class WhatsAppService {
  private sock: WASocket | null = null;
  private qr: string | null = null;
  private isConnecting = false;

  public isConnected(): boolean {
    return Boolean(this.sock && this.sock.user);
  }

  public getQr(): string | null {
    return this.isConnected() ? null : this.qr;
  }

  public getUser() {
    if (!this.sock?.user) return null;
    return {
      id: this.sock.user.id,
      phone: this.sock.user.id?.split(":")?.[0] || this.sock.user.id,
      name: this.sock.user.name || null,
    };
  }

  public async init(): Promise<void> {
    if (this.isConnecting) return;
    this.isConnecting = true;

    try {
      const { state, saveCreds } = await useMultiFileAuthState(config.authDir);

      this.sock = makeWASocket({
        auth: state,
        logger: pino({ level: "silent" }),
        markOnlineOnConnect: false,
      });

      this.sock.ev.on("creds.update", saveCreds);

      this.sock.ev.on("connection.update", (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr) {
          this.qr = qr;
          console.log("\n====================================");
          console.log("SCAN THIS QR CODE WITH WHATSAPP:");
          console.log("====================================");
          qrcode.generate(qr, { small: true });
          console.log("Raw QR String available at GET /qr\n");
        }

        if (connection === "open") {
          console.log("Connected as:", this.sock?.user?.id);
          this.qr = null;
          this.isConnecting = false;
        }

        if (connection === "close") {
          this.isConnecting = false;
          this.sock = null;

          const statusCode = (lastDisconnect?.error as Boom)?.output?.statusCode;
          console.log(`WhatsApp disconnected (status code: ${statusCode || "unknown"})`);

          if (statusCode === DisconnectReason.loggedOut) {
            console.log("Logged out. Resetting auth directory for new QR generation.");
            this.qr = null;
            try {
              fs.rmSync(config.authDir, { recursive: true, force: true });
            } catch (err) {
              console.error("Error clearing auth directory:", err);
            }
            setTimeout(() => this.init(), 3000);
            return;
          }

          console.log("Reconnecting in 5 seconds...");
          setTimeout(() => this.init(), 5000);
        }
      });

      this.sock.ev.on("messages.upsert", async ({ messages }) => {
        for (const msg of messages) {
          await this.handleInboundMessage(msg);
        }
      });
    } catch (error) {
      this.isConnecting = false;
      this.sock = null;
      console.error("Failed to initialize WhatsApp connection:", error);
      setTimeout(() => this.init(), 5000);
    }
  }

  private async handleInboundMessage(msg: any): Promise<void> {
    try {
      if (!msg.message || msg.key.fromMe) return;

      const remoteJid = msg.key.remoteJid || "";

      // 1-on-1 direct messaging only: ignore groups & status broadcasts
      if (remoteJid.endsWith("@g.us") || remoteJid.includes("broadcast")) return;

      const text =
        msg.message.conversation ||
        msg.message.extendedTextMessage?.text ||
        msg.message.imageMessage?.caption ||
        msg.message.videoMessage?.caption ||
        "";

      const phone = remoteJid.replace("@s.whatsapp.net", "");

      const payload = {
        from: phone,
        jid: remoteJid,
        senderName: msg.pushName || null,
        text,
        messageId: msg.key.id,
        timestamp: Number(msg.messageTimestamp),
      };

      console.log(`Inbound message from ${phone}: "${text.slice(0, 60)}"`);

      await axios.post(config.mainServiceInboundUrl, payload, { timeout: 5000 });
    } catch (error: any) {
      if (error.config?.url) {
        console.error(
          `Failed to dispatch inbound message to ${config.mainServiceInboundUrl}:`,
          error.message
        );
      } else {
        console.error("Error processing inbound message:", error);
      }
    }
  }

  public async sendMessage(
    to: string,
    message: string
  ): Promise<{ messageId: string | null; to: string }> {
    if (!this.sock || !this.sock.user) {
      const err: any = new Error("WhatsApp is not connected or authenticated.");
      err.statusCode = 503;
      throw err;
    }

    const digits = to.replace(/[^0-9]/g, "");
    if (!digits) {
      const err: any = new Error("Invalid phone number provided.");
      err.statusCode = 400;
      throw err;
    }

    const jid = to.includes("@") ? to : `${digits}@s.whatsapp.net`;
    const result = await this.sock.sendMessage(jid, { text: message });

    console.log(`Outbound message sent to ${digits} (ID: ${result?.key?.id})`);

    return {
      messageId: result?.key?.id || null,
      to: digits,
    };
  }
}

export const whatsapp = new WhatsAppService();
