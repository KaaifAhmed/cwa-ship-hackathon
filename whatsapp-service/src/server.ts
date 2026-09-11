import express, { Request, Response } from "express";
import { config } from "./config.js";
import { whatsapp } from "./whatsapp.js";

const app = express();
app.use(express.json({ limit: "256kb" }));

/**
 * Health & WhatsApp connection status
 */
app.get("/health", (_req: Request, res: Response) => {
  const isConnected = whatsapp.isConnected();

  res.json({
    status: "ok",
    connected: isConnected,
    authenticated: isConnected,
    user: whatsapp.getUser(),
    inboundWebhook: config.mainServiceInboundUrl,
  });
});

/**
 * Raw QR string for pairing via main backend / frontend UI
 */
app.get("/qr", (_req: Request, res: Response) => {
  const isConnected = whatsapp.isConnected();
  const qr = whatsapp.getQr();

  res.json({
    success: true,
    authenticated: isConnected,
    connected: isConnected,
    qr,
    message: isConnected
      ? "WhatsApp is already connected."
      : qr
      ? "QR code available."
      : "QR code is generating, please retry shortly.",
  });
});

/**
 * Outbound 1-on-1 message sending
 */
app.post(["/whatsapp/send", "/api/whatsapp/send"], async (req: Request, res: Response) => {
  const to = (req.body.to || req.body.phone || req.body.recipient || "").toString().trim();
  const message = (req.body.message || req.body.text || "").toString();

  if (!to) {
    return res.status(400).json({
      success: false,
      error: "Recipient phone number ('to') is required.",
    });
  }

  if (!message || message.trim().length === 0) {
    return res.status(400).json({
      success: false,
      error: "Message content ('message') cannot be empty.",
    });
  }

  try {
    const result = await whatsapp.sendMessage(to, message);
    return res.json({ success: true, ...result });
  } catch (error: any) {
    const status = error.statusCode || 500;
    return res.status(status).json({
      success: false,
      error: error.message || "Failed to send WhatsApp message.",
    });
  }
});

// Start Express server and initialize WhatsApp Web
app.listen(config.port, () => {
  console.log(`WhatsApp Gateway running on port ${config.port}`);
  console.log(`Inbound Webhook configured to: ${config.mainServiceInboundUrl}`);
  whatsapp.init();
});
