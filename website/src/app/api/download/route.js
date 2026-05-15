import { NextResponse } from "next/server";
import { LATEST_RELEASE_API_URL } from "@/consts";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const response = await fetch(LATEST_RELEASE_API_URL, { cache: "no-store" });
    const data = await response.json();
    const downloadableAsset = data?.assets?.find((asset) =>
      /\.(zip|dmg)$/i.test(asset.name)
    );
    const downloadUrl = downloadableAsset?.browser_download_url;

    if (!downloadUrl) {
      return NextResponse.json(
        { error: "No downloadable release asset found" },
        { status: 404 }
      );
    }

    return NextResponse.redirect(downloadUrl);
  } catch (error) {
    console.error(error);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}
