const eventTypes = {
    "onclick": "click"
};

let h = function(eName, ...args) {
    let type = eName;
    let elem = document.createElement(type);
    function processArgs(args) {
        for(let a of args) {
            if(Array.isArray(a)) {
                processArgs(a);
            }
            else if(typeof(a) === "string") {
                elem.innerHTML += a;
            }
            else if(a instanceof HTMLElement) {
                elem.appendChild(a);
            }
            else if(typeof(a) === "object") {
                for(let [key, value] of Object.entries(a)) {
                    if(key === "parent") {
                        value.appendChild(elem);
                    }
                    else if(eventTypes[key]) {
                        elem.addEventListener(eventTypes[key], value);
                    }
                    else {
                        elem.setAttribute(key, value);
                    }
                }
            }
            else {
                throw new Error(`Unexpected argument ${a}`);
            }
        }
    }
    processArgs(args);
    return elem;
}

function lightbox() {
    let lbImg =
        h("img",
          {
              class: "lightbox-img",
              src: "/images/gallery/_RL80848.jpg"
          }
         );

    let lbNext =
        h("div", { class: "lightbox-next" },
          h("i", { class: "fa fa-solid fa-arrow-right" })
         );
    let lbPrev =
        h("div", { class: "lightbox-prev" },
          h("i", { class: "fa fa-solid fa-arrow-left" })
         );

    let lightbox =
        h("div",
          {
              class: "lightbox-bg",
              parent: document.querySelector("body"),
              onclick: (ev) => {
                  console.log("ANH");
                  lightbox.classList.remove("active");
                  lbImg.setAttribute("src", "");
                  ev.preventDefault();
                  ev.stopPropagation();
              }
          },
          lbPrev,
          lbNext,
          lbImg
         );

    let replaceNode = (node) => {
        let newNode = node.cloneNode(true);
        node.parentNode.replaceChild(newNode, node);
        return newNode;
    }

    let links = document.querySelectorAll(".lightbox-link");
    for(let [i, link] of links.entries()) {
        let activate = (i) => (ev) => {
            let link = links[i];
            let next = links[i+1];
            let prev = links[i-1];
            let href = link.attributes["href"].value;

            console.log(i, link, next, prev, href);

            lbImg.setAttribute("src", href);
            lightbox.classList.add("active");

            lbPrev.classList.remove("active");
            lbPrev = replaceNode(lbPrev);

            lbNext.classList.remove("active");
            lbNext = replaceNode(lbNext);

            if(prev) {
                lbPrev.classList.add("active");
                lbPrev.addEventListener('click', activate(i-1));
            }

            if(next) {
                lbNext.classList.add("active");
                lbNext.addEventListener('click', activate(i+1));
            }

            ev.preventDefault();
            ev.stopPropagation();
        }
        link.addEventListener('click', activate(i));
    }
}

lightbox();

export {lightbox as default};