import { FaGithub, FaApple } from "react-icons/fa6";
import DownloadWrapper from "./DownloadWrapper";
import { GITHUB_URL } from "@/consts";

const navItems = [
  { label: "What?", href: "#what-it-is" },
  { label: "Why?", href: "#why-yeoldbackup" },
  { label: "How?", href: "#how-it-works" },
  { label: "Get Started", href: "#getting-started" },
  { label: "FAQ", href: "#faq" },
];

const Navbar = () => {
  return (
    <div className="py-4 flex justify-between items-center border-b border-gray-200">
      <span className="font-bold">YeOldBackup</span>
      <div className="flex gap-5 items-center">
        <div className="gap-3 items-center text-sm font-semibold hidden md:flex">
          {navItems.map((item) => (
            <a href={item.href} key={item.label} className="hover:text-primary">
              {item.label}
            </a>
          ))}
        </div>
        <div className="flex gap-2 items-center">
          {" "}
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            <MiniNavBtn>
              <FaGithub />
              GitHub
            </MiniNavBtn>
          </a>
          <MiniNavBtn>
            <DownloadWrapper className="flex items-center gap-2">
              <FaApple />
              Download
            </DownloadWrapper>
          </MiniNavBtn>
        </div>
      </div>
    </div>
  );
};

export default Navbar;

const MiniNavBtn = ({ children }) => {
  return (
    <div className="text-sm font-semibold px-2 py-1 rounded-md bg-gray-200 hover:bg-primary/10 transition flex items-center gap-2">
      {children}
    </div>
  );
};
