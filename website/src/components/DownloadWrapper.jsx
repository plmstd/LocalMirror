import React from "react";

const DownloadWrapper = ({ children, className }) => {
  const url = "/api/download";

  return (
    <a href={url} className={className}>
      {children}
    </a>
  );
};

export default DownloadWrapper;
