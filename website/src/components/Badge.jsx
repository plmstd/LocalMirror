import React from "react";

const Badge = ({
  children,
  bgColor = "bg-gray-200 hover:bg-primary/10",
  borderColor = "border-gray-300 hover:border-primary",
  cursor = "hover:cursor-default",
  textColor = "text-text",
  className,
}) => {
  return (
    <div
      className={`text-sm font-semibold px-4 py-1 rounded-full ${bgColor} border ${borderColor} ${cursor} ${textColor} transition flex items-center gap-2 ${className}`}
    >
      {children}
    </div>
  );
};

export default Badge;
