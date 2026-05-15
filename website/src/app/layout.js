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
          data-domain="localmirror.app"
          src="https://plausible.io/js/script.outbound-links.js"
          strategy="beforeInteractive"
        />
        <Script
          defer
          data-website-id="dfid_xltNNhntkEpvH9oOlho2Q"
          data-domain="www.localmirror.app"
          src="https://datafa.st/js/script.js"
        />
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
