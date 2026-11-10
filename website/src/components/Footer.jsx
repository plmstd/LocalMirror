import {AnalyticsSettingsButton} from './AnalyticsConsent';
import { FaXTwitter } from "react-icons/fa6";
import { GITHUB_URL } from "@/consts";

const Footer = () => {
  return (
    <div className="py-2 flex justify-between items-center border-t border-gray-200 text-sm">
      <div className="font-medium flex gap-2 items-center">
        LocalMirror is created by{" "}
        <a href="https://www.palmio.io" className="text-blue-500 font-bold">
          palmio
        </a>
        |{" "}
        <div>
          <a
            href="https://x.com/bennyqp"
            target="_blank"
            rel="noopener noreferrer"
            className="flex gap-1 items-center"
          >
            <FaXTwitter />
            bennyqp
          </a>
        </div>
      </div>
      <div className="flex gap-5 items-center flex-wrap">
        <AnalyticsSettingsButton />
        <a href="/privacy">Privacy policy</a>
        <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
          GitHub
        </a>
      </div>
    </div>
  );
};

export default Footer;
