import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://airdropper-mac.cosmintrricaa.chatgpt.site"),
  title: "AirFliq - Select. Fliq. Sent.",
  description:
    "The beautifully fast way to prepare files for AirDrop from Finder, a shortcut, the menu bar, or a drag gesture.",
  icons: {
    icon: "/assets/airfliq-icon.png",
    shortcut: "/assets/airfliq-icon.png",
    apple: "/assets/airfliq-icon.png",
  },
  openGraph: {
    title: "AirFliq - Select. Fliq. Sent.",
    description: "Your first 50 successful sends are free. Lifetime Pro is $4.99.",
    type: "website",
    images: [
      {
        url: "/og-airfliq.png",
        width: 1200,
        height: 630,
        alt: "AirFliq - Select. Fliq. Sent.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "AirFliq - Select. Fliq. Sent.",
    description: "Your first 50 successful sends are free. Lifetime Pro is $4.99.",
    images: ["/og-airfliq.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
