import { Link } from "react-router-dom";
import { Card, Empty } from "../components/Ui";
import { usePageTitle } from "../lib/hooks";

export function NotFound() {
  usePageTitle("Not found");
  return (
    <div className="page">
      <Card>
        <Empty
          title="No such hall in this castle"
          action={
            <Link className="btn" to="/">
              Back to the throne room
            </Link>
          }
        >
          The page you asked for doesn't exist.
        </Empty>
      </Card>
    </div>
  );
}
