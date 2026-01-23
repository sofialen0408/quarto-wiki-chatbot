# Welcome to the PA Knowledge Base Repo!

[This knowledge base](https://dev.ochco-connect.ochco.nasa.gov/pa-knowledge-base/) holds the People Analytics team's documentation, including employee resources, functional areas, data dictionaries and management, the People Analytics Cloud (PAC) Environment and Integrations, and Technology & Analytics references. If you run into any issues, reach out to David Meza or Madison Ostermann.

# Getting Started

-   If this is your first time working on the Quarto site, clone this [repository](https://developer.nasa.gov/ochco/pa-knowledge-base). This step will only need done once, ever, for this repository.
-   Open up the repository folder (likely labeled `pa-knowledge-base`) in your IDE of choice, RStudio or Positron is easiest because it will later facilitate easy rendering of the site.
-   Check that you are on the `development` branch and have fetched & pulled any recent changes before making your own.
-   Expand the "site" folder to view the `.qmd` files that are the basis of the Quarto website, and what we primarily edit and add to.
    -   Note that when Quarto previews & publishes, really what it's doing is taking these `.qmd` files in the "site" folder and rendering them as `.html` files, which are placed in the "\_site" folder and actually referenced when the website is deployed on `localhost` or Posit Connect.
-   With either RStudio or Positron, edit the `.qmd` files you need - Quarto has great documentation about [Markdown Basics](https://quarto.org/docs/authoring/markdown-basics.html) to assist with the small learning curve.
    -   If you are adding a new `.qmd` file, there are some tips we can provide to make this addition seamless!
        -   Add the new document in the desired folder, using `.qmd` as the extension.
        -   In the YAML header of that document, include the same title, author, date, and draft fields (if applicable) you see across other `.qmd` files of the site.
        -   **For adding photos:** Make sure you download pictures into the `media` folder and link accordingly. The format should look like this when adding a picture \![ \](site/media/ \_\_\_\_\_\_.png).
        -   Anytime you add a new `.qmd` file to the project directory, you must "register" it in the file that acts as the skeleton of the entire website body, `\_quarto.yml` for it to actually appear on the website. This file is located in the OUTERMOST folder - do **NOT** change the name to anything but `\_quarto.yml`.
            -   Every website has a `_quarto.yml` config file that provides website options as well as defaults for HTML documents created within the site. For example, here is the default config file a simple site:
-   In RStudio, click on **Build** in the upper right corner (in between connections and git)
-   Press on Render Website and wait for the site to render
-   In Positron, select the qmd file, press ctrl+shift+K to render. You may need to download [Quarto](https://quarto.org/docs/get-started/) and install the extension.

                ```         
                website:
                  navbar:
                background: primary
                search: true
                left:
                  - text: "Home"
                    href: index.qmd
                  - talks.qmd
                  - about.qmd
                ```

            -   **Indentation matters**. The "project" section creates the website. The "website" section contains the footer, navbar (which is the blue top feature), and the sidebar (which is different per each navigation section).
        -   Add the new `.qmd` file to this `\_quarto.yml` file in the same fashion you see other files; include the name of the page and a file path link to the document. **Remember, indentation matters.** Organize it under the area you think it would fit the best, consulting the team if needed!
-   Preview your changes by deploying the website locally - it may take a few minutes to render the first time around, so go grab a coffee!
    -   In RStudio, click on **Build** in the upper right corner (in between "connections" and "git"). Then click "Render Website" and wait for the site to render locally. ![](/site/media/render-website.png)
    -   In Positron, ensure you have the `index.qmd` file selected, and either click the "Preview" icon in-line with the file tabs, or use the `Shift + Cmd + K` shortcut (on Mac at least). The preview should appear in the viewer pane to the right of any open files, but you can also open up the `localhost` URL in your browser.
-   Keep making your edits & previewing your changes until you are a) happy with the outcome and b) have ensured that the site still builds successfully!
-   Make sure to commit your changes to the development branch, with a decently descriptive commit message. If you have left your edits hanging open for a while, it's possible other team members have edited the same content over the same period of time, and you may have to resolve merge conflicts.
    -   After you commit to the development branch, changes will be merged into the main branch after being tested & approved, and Github Actions will facilitate the auto-publishing of the website from here!

See our [Contribution Guide in the Knowledge Base Site](https://dev.ochco-connect.ochco.nasa.gov/pa-knowledge-base/site/employee-resources/contributing-quarto/contribution-guide.html) for more information on how to contribute!!