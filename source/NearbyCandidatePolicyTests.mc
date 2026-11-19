import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyCandidateAcquisitionPolicy(logger as Logger) as Boolean {
    Test.assertMessage(NearbyCandidatePolicy.shouldRequest(null, false, false, false,
        false, false, 7), "pending unshown candidate gets an initial response");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(["key"], false, false, false,
        false, false, 7), "known candidate is not refetched");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, true, false, false,
        false, false, 7), "overflow cannot be repaired by another response this session");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, false, true, false,
        false, false, 7), "no repeated unknown candidate fetch this session");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, false, false, true,
        false, false, 7), "pages use the ordinary scheduler");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, false, false, false,
        true, false, 7), "existing request is not duplicated");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, false, false, false,
        false, true, 7), "one extra in flight");
    Test.assertMessage(!NearbyCandidatePolicy.shouldRequest(null, false, false, false,
        false, false, 8), "eight-request cycle cap");
    return true;
}
