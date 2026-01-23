document.addEventListener("DOMContentLoaded", function() {
  const navLinks = document.querySelectorAll(".nav-link");

  navLinks.forEach(function(link) {
    link.addEventListener("click", function(event) {
      event.preventDefault();

      navLinks.forEach(function(link) {
        link.classList.remove("active");
      });

      link.classList.add("active");
    });
  });
});

    document.addEventListener("DOMContentLoaded", function() {
        var footer = document.querySelector("footer");
        var scrollThreshold = 100; // Adjust this value as needed

        function toggleFooterVisibility() {
            var scrollHeight = document.documentElement.scrollHeight;
            var clientHeight = window.innerHeight;
            var scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;

            if (scrollHeight - scrollTop <= clientHeight + scrollThreshold) {
                footer.style.display = "block";
            } else {
                footer.style.display = "none";
            }
        }

        window.addEventListener("scroll", toggleFooterVisibility);
    });

