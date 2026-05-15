import { IoWarningOutline } from "react-icons/io5";

const InfoBox = ({ type, className, children }) => {
  return (
    <div
      className={`p-4 text-sm font-medium rounded-md flex gap-5 ${
        type === "warn"
          ? "bg-amber-200 border border-amber-300"
          : "bg-blue-100 border-blue-200"
      } ${className}`}
    >
      <IoWarningOutline className="text-3xl text-amber-500" />
      <div>{children}</div>
    </div>
  );
};

export default InfoBox;
