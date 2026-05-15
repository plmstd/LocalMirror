import Markdown from "react-markdown";
import LinkRenderer from "@/components/LinkRenderer";
import {
  whatItIscontent,
  whyYouMightLikeItContent,
  howItWorksContent,
  useWithCautionContent,
  gettingStartedContent,
  faqContent,
  aboutContent,
  contributingContent,
} from "@/content/HomeMainContent";

const ExtendedMarkdown = ({ children, id }) => {
  return (
    <div id={id} className="">
      <Markdown components={{ a: LinkRenderer }}>{children}</Markdown>
    </div>
  );
};

const MainContent = () => {
  return (
    <div className="markdown">
      <ExtendedMarkdown id="what-it-is">{whatItIscontent}</ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="why-yeoldbackup">
        {whyYouMightLikeItContent}
      </ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="how-it-works">{howItWorksContent}</ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="use-with-caution">
        {useWithCautionContent}
      </ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="getting-started">
        {gettingStartedContent}
      </ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="faq">{faqContent}</ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="about">{aboutContent}</ExtendedMarkdown>
      <hr />
      <ExtendedMarkdown id="contributing">
        {contributingContent}
      </ExtendedMarkdown>
    </div>
  );
};

export default MainContent;
