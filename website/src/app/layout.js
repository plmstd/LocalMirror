import "@/styles/globals.css";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import Script from "next/script";

export const metadata = {
  title: "LocalMirror",
  description: "Minimalistic File Sync and Backup Utility for MacOs",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <head>
        <Script
          defer
          data-website-id="dfid_xltNNhntkEpvH9oOlho2Q"
          data-domain="www.localmirror.app"
          src="https://datafa.st/js/script.js"
        />
        <link
          rel="icon"
          type="image/png"
          href="/favicon/favicon-96x96.png?v=20260515"
          sizes="96x96"
        />
        <link
          rel="icon"
          type="image/svg+xml"
          href="/favicon/favicon.svg?v=20260515"
        />
        <link rel="shortcut icon" href="/favicon/favicon.ico?v=20260515" />
        <link
          rel="apple-touch-icon"
          sizes="180x180"
          href="/favicon/apple-touch-icon.png?v=20260515"
        />
        <meta name="apple-mobile-web-app-title" content="LocalMirror" />
        <link rel="manifest" href="/favicon/site.webmanifest?v=20260515" />
      </head>
      <body className={`antialiased`}>
        <div className="mb-10 lg:mb-16">
          <Navbar />
        </div>
        <div className="content">{children}</div>
        <div className="mt-10 lg:mt-16">
          <Footer />
        </div>
      </body>
    </html>
  );
}
