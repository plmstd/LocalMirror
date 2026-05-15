import { NextResponse } from "next/server";
import { LATEST_RELEASE_API_URL } from "@/consts";

export async function GET() {
  try {
    const response = await fetch(LATEST_RELEASE_API_URL);
    const data = await response.json();
    // get first zip file from assets
    const zipFile = data?.assets?.find((asset) => asset.name.endsWith(".zip"));
    const downloadUrl = zipFile?.browser_download_url;
    if (!downloadUrl) {
      return NextResponse.json({ error: "No zip file found" }, { status: 404 });
    }

    // Optional: Direkt weiterleiten
    return NextResponse.redirect(downloadUrl);

    // Oder: Gib den Link nur zurück (falls du den Download erst im Frontend triggern willst)
    // return NextResponse.json({ downloadUrl: asset.browser_download_url });
  } catch (error) {
    console.error(error);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}
