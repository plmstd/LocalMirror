import Image from "next/image";
import { FaGithub, FaApple } from "react-icons/fa6";
import MainContent from "@/components/MainContent";
import Badge from "@/components/Badge";
import { GITHUB_URL } from "@/consts";
import InfoBox from "@/components/InfoBox";
import Button from "@/components/Button";
import DownloadWrapper from "@/components/DownloadWrapper";

export default function Home() {
  return (
    <div>
      <div className="">
        <h1 className="text-4xl font-bold mb-4">LocalMirror</h1>
        <div className="flex gap-2 items-center mb-5 flex-wrap">
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            <Badge
              bgColor="bg-gray-800 hover:bg-gray-950"
              textColor="text-white"
              borderColor="border-gray-950"
              cursor="hover:cursor-pointer"
            >
              <FaGithub /> GitHub Repo
            </Badge>
          </a>
          <Badge
            bgColor="bg-primary/10 hover:bg-primary/20"
            borderColor="border-primary/30 hover:border-primary/40"
          >
            Open Source
          </Badge>
          <Badge
            bgColor="bg-purple-100 hover:bg-purple-200"
            borderColor="border-purple-300 hover:border-purple-400"
          >
            PRs Welcome
          </Badge>

          <Badge
            bgColor="bg-orange-100 hover:bg-yellow-500"
            borderColor="border-orange-200 hover:border-yellow-600"
            textColor="text-white"
            className="uppercase font-extrabold group"
          >
            <div>
              <span className="group-hover:text-white text-red-600 relative -top-[0.5px] transition">
                V
              </span>
              <span className="group-hover:text-white text-blue-600 relative top-[0.5px] transition">
                i
              </span>
              <span className="group-hover:text-white text-green-600 relative -top-[0.5px] transition">
                b
              </span>
              <span className="group-hover:text-white text-yellow-600 relative top-[0.5px] transition">
                e
              </span>{" "}
              <span className="group-hover:text-white text-purple-600 relative -top-[0.5px] transition">
                C
              </span>
              <span className="group-hover:text-white text-orange-600 relative top-[0.5px] transition">
                o
              </span>
              <span className="group-hover:text-white text-pink-600 relative -top-[0.5px] transition">
                d
              </span>
              <span className="group-hover:text-white text-orange-600 relative top-[0.5px] transition">
                e
              </span>
              <span className="group-hover:text-white text-blue-600 relative -top-[0.5px] transition">
                d
              </span>
            </div>
          </Badge>
        </div>
        <InfoBox type="warn" className="mb-5">
          <p>
            LocalMirror is vibe coded (primarily AI-generated) and may not
            function as intended. It could contain bugs or exhibit unpredictable
            behavior. Use at your own risk.
          </p>
        </InfoBox>
        <p className="mb-5 font-medium">
          A lightweight macOS app designed to sync folders or hard drives using{" "}
          <a
            className="bg-gray-200 px-1 rounded-sm"
            href="https://en.wikipedia.org/wiki/Rsync"
            target="_blank"
            rel="noopener noreferrer"
          >
            rsync
          </a>
          , complete with a simple GUI. Open source. Minimalist. Vibe coded.
        </p>
        <div className="flex gap-2 mb-10">
          <DownloadWrapper>
            <Button>
              <div className="flex gap-2 items-center">
                <FaApple /> Download for macOS
              </div>
            </Button>
          </DownloadWrapper>
        </div>
        <Image
          src="/images/localmirror-screenshot-02.jpg"
          alt="LocalMirror"
          width={6000}
          height={0}
          className="rounded-lg bg-primary/10"
        />
      </div>
      <MainContent />
    </div>
  );
}
