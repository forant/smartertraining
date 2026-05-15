import Foundation

enum TCXGenerator {

    static func generate(from workout: CompletedWorkout) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
                                xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2"
                                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(iso8601(workout.startDate))</Id>
              <Lap StartTime="\(iso8601(workout.startDate))">
                <TotalTimeSeconds>\(workout.duration)</TotalTimeSeconds>
                <DistanceMeters>0.0</DistanceMeters>
                <Calories>0</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>

        """

        for sample in workout.samples {
            xml += "          <Trackpoint>\n"
            xml += "            <Time>\(iso8601(sample.timestamp))</Time>\n"

            if let cadence = sample.cadence {
                xml += "            <Cadence>\(Int(cadence))</Cadence>\n"
            }

            if let hr = sample.heartRate {
                xml += "            <HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>\n"
            }

            if let power = sample.power {
                xml += "            <Extensions>\n"
                xml += "              <ns3:TPX>\n"
                xml += "                <ns3:Watts>\(power)</ns3:Watts>\n"
                xml += "              </ns3:TPX>\n"
                xml += "            </Extensions>\n"
            }

            xml += "          </Trackpoint>\n"
        }

        xml += """
                </Track>
              </Lap>
              <Creator xsi:type="Device_t">
                <Name>SmarterTraining</Name>
              </Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """

        return Data(xml.utf8)
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
