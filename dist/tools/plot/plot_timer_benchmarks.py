#!/usr/env python3

import os
import argparse
import warnings
from ast import literal_eval

import xml.etree.ElementTree as ET
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go


class FigurePlotter:
    def __init__(self, input, outdir, ci_build):
        self.root = ET.parse(input).getroot()
        self.outdir = outdir
        if ci_build:
            self.plotlyjs = False
            self.full_html = False
        else:
            self.plotlyjs = "cdn"
            self.full_html = True

        version = self.root.find(".//property[@name='timer-version']")
        if version is None:
            raise RuntimeError("timer version not found")
        self.timer_version = version.get("value")

    def plot_accuracy(self, filename):
        # parse
        accuracy_rows = []
        for prop in self.root.findall(
            "testcase[@classname='tests_{}_benchmarks.Sleep Accuracy']//property".format(
                self.timer_version
            )
        ):
            name = prop.get("name").split("-")
            if "TIMER_SLEEP" in name:
                function = "TIMER_SLEEP"
            elif "TIMER_SET" in name:
                function = "TIMER_SET"
            else:
                raise LookupError

            result_type = name[-1]
            target = literal_eval(name[-2]) / 1000000

            actual = literal_eval(prop.get("value"))
            if result_type == "dut":
                # dut results are in microseconds, convert to seconds to uniform with philip results
                actual = [v / 1000000 for v in actual]

            for i, v in enumerate(actual):
                accuracy_rows.append(
                    {
                        "repeat": i,
                        "target_duration": target,
                        "actual_duration": v,
                        "function": function,
                        "result_type": result_type,
                        "diff_actual_target": v - target,
                    }
                )

        df = pd.DataFrame(
            [row for row in accuracy_rows if row["result_type"] == "philip"]
        )
        if df.empty:
            return

        # plot
        df = (
            df.groupby(["function", "target_duration"])
            .describe()["diff_actual_target"]
            .reset_index()
        )
        fig = px.line(df, x="target_duration", y="mean", color="function")

        fig.update_layout(
            dict(
                title="Sleep Accuracy",
                xaxis_title="Target Sleep Duration (s)",
                yaxis_title="Difference Actual - Target Sleep Duration (s)",
            ),
            legend_orientation="h",
        )

        fig.write_html(
            "{}/{}".format(self.outdir, filename),
            full_html=self.full_html,
            include_plotlyjs=self.plotlyjs,
        )

    def plot_jitter(self, filename):
        df = {"timer_count": [], "sleep_duration": [], "divisor": []}
        for testcase in self.root.findall(
            f"testcase[@classname='tests_{self.timer_version}_benchmarks.Sleep Jitter']"
        ):
            timer_count = len(
                literal_eval(
                    testcase.find("properties/property[@name='intervals']").get("value")
                )
            )
            divisor = literal_eval(
                testcase.find("properties/property[@name='divisor']").get("value")
            )
            traces = literal_eval(
                testcase.find("properties/property[@name='trace']").get("value")
            )

            df["sleep_duration"].extend(traces)
            df["timer_count"].extend([int(timer_count)] * len(traces))
            if "Divisor" in testcase.get("name"):
                df["divisor"].extend([divisor] * len(traces))
            else:
                # divisor None means = 1, not used when varying timer count
                df["divisor"].extend([None] * len(traces))

        df = pd.DataFrame(df)
        if df.empty:
            return

        drop = df[
                (df["timer_count"] > 30) | (df["timer_count"] < 0)
            ].index
        df.drop(drop, inplace=True)

        df["sleep_duration_target_diff"] = df["sleep_duration"] - (
            [0.1] * len(df["sleep_duration"])
        )

        df["sleep_duration_percentage"] = (df["sleep_duration"] / 0.100) * 100

        fig = px.violin(
            df[df["divisor"].isnull()],
            x="timer_count",
            y="sleep_duration_target_diff",
            color="timer_count",
            points="all",
        )

        fig.update_layout(
            title="Jitter of periodic 100ms sleep with increasing nr. of background timer",
            yaxis_title="Actual Sleep Duration[%]",
            xaxis_title="Nr. of background timers",
            legend_orientation="h",
        )

        fig.write_html(
            "{}/{}".format(self.outdir, filename),
            full_html=self.full_html,
            include_plotlyjs=self.plotlyjs,
        )

    def get_drift_df(self):
        dss = list()
        for testcase in self.root.findall(
            f"testcase[@classname='tests_{self.timer_version}_benchmarks.Drift']"
        ):

            for prop in testcase.findall(".//property"):
                # name formatted as 'name'-'unit', we ditch the unit
                name = prop.get("name").split("-")

                repeat_n = int(name[name.index("repeat") + 1])  # repeat count
                # values are recorded as string, convert to float
                value = literal_eval(prop.get("value"))
                # make sure value not in array
                if len(value) == 1:
                    value = value[0]

                value_source = "dut" if "dut" in name else "philip"

                key = int(name[2]) / 1_000_000

                # create a new row or update if already existed
                try:
                    row = next(
                        e for e in dss if e["time"] == key and e["repeat"] == repeat_n
                    )
                    row.update(
                        {
                            "time": key,
                            "repeat": repeat_n,
                            value_source: value,
                        }
                    )
                except StopIteration:
                    row = {
                        "time": key,
                        "repeat": repeat_n,
                        value_source: value,
                    }
                    dss.append(row)

        df = pd.DataFrame(dss, dtype="float64")
        # combine dut, philip rows with same (time, repeat) to remove NaN values
        df = df.groupby(["time", "repeat"]).sum()
        df["diff_dut_philip"] = df["dut"] - df["philip"]
        df["diff_percentage"] = df["diff_dut_philip"] / df["dut"] * 100
        df.reset_index(["time", "repeat"], inplace=True)
        return df

    def plot_drift_diff(self, filename):
        df = self.get_drift_df()
        if df.empty:
            return

        fig = px.box(df, x="time", y="diff_dut_philip", color="time")
        fig.add_trace(
            go.Scatter(
                x=df["time"].unique(),
                y=df.groupby("time").mean()["diff_dut_philip"].array,
            )
        )

        fig.write_html(
            "{}/{}".format(self.outdir, filename),
            full_html=self.full_html,
            include_plotlyjs=self.plotlyjs,
        )

    def plot_drift_percentage(self, filename):
        df = self.get_drift_df()
        if df.empty:
            return

        fig = px.box(df, x="time", y="diff_percentage", color="time")

        fig.update_layout(
            title=f"Drift for Sleep Duration {df['time'].min()} - {df['time'].max()} seconds",
            yaxis_title="Percentage Actual/Given Sleep Duration [%]",
            xaxis_title="Sleep Duration [s]",
            legend_orientation="h",
        )

        # to add max line based on board info
        # fig.update_layout(shapes=[

        #     dict(
        #         type='line',
        #         yref= 'y', y0=0.2, y1=0.2,
        #         xref= 'x', x0=0, x1=30,
        #     )
        # ])

        fig.write_html(
            "{}/{}".format(self.outdir, filename),
            full_html=self.full_html,
            include_plotlyjs=self.plotlyjs,
        )

    def plot_overhead(self, filename):
        bres = {"row": [], "test": [], "time": []}

        tests = [
            t
            for t in self.root.findall(
                f"testcase[@classname='tests_{self.timer_version}_benchmarks.Timer Overhead']//property"
            )
            if "overhead" in t.get("name")
        ]
        for t in tests:
            values = literal_eval(t.get("value"))
            bres["time"].extend(values)
            name = t.get("name").split("-")
            bres["row"].extend([name[1]] * len(values))
            bres["test"].extend([" ".join(name[2:])] * len(values))

        df = pd.DataFrame(bres)
        if df.empty:
            return

        columns = ["test", "mean", "std", "min", "max"]
        grouped = df.groupby(["row", "test"])["time"].describe().reset_index()
        fig = go.Figure(
            go.Table(
                header=dict(values=columns),
                cells=dict(
                    values=[grouped[col] for col in columns],
                    align="center",
                    format=[[None], [".5s"]],
                ),
            )
        )

        fig.update_layout(
            height=200,
            margin=dict(
                autoexpand=True,
                t=5,
                l=0,
                r=0,
                b=5,
            ),
        )

        fig.write_html(
            "{}/{}".format(self.outdir, filename),
            full_html=self.full_html,
            include_plotlyjs=self.plotlyjs,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Produce timer benchmarks plots from xunit results"
    )

    parser.add_argument("input", help="xunit result file to parse")
    parser.add_argument(
        "--outdir", help="output directory to write plots to", default="."
    )
    parser.add_argument(
        "--for-ci",
        help="configure output for ci (this will exclude plotly.js from output files)",
        action="store_true",
    )

    args = parser.parse_args()

    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    plotter = FigurePlotter(args.input, args.outdir, args.for_ci)
    plotter.plot_overhead("overhead.html")
    plotter.plot_accuracy("accuracy.html")
    plotter.plot_jitter("jitter.html")
