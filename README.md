# 🌏Our Planet

**Raywenderlich—RxSwift: Reactive Programming with Swift에서 학습한 내용을 바탕으로 작성함**

---

## How Our Planet Works

User Interface (Soem View Controllers) ↔ Network Service, especially ***EONET*** **service** **(NASA's *Earth Observatory Natural Event Tracker*)

**Key Tasks**

- EONET API (https://eonet.sci.gsfc.nasa.gov/docs/v2.1)로부터 모든 카테고리 (For example, Drought, Dust and Haze, ...)를 가져와 이를 첫번째 화면에 표현한다.
    - 각각의 카테고리에 대해 이벤트들을 불러오고 그 개수를 보여준다.
- 사용자가 카테고리를 탭하면, 해당 카테고리의 이벤트들을 보여준다.

**User Interface**

- Two View Controllers
    - CategoriesViewController
        - 카테고리와 각 카테고리 별 이벤트 개수를 불러온다.
    - EventsViewController
        - 사용자가 탭한 카테고리의 이벤트들을 보여준다.

**EONET Model**

- EOEnvelope
- EOCategory
    - `id: String`—카테고리 식별자
    - `title: String`—카테고리 제목
    - `description: String`—카테고리 설명
    - `events: [EOEvent]`—해당 카테고리에 속하는 0개 또는 하나 이상의 이벤트 묶음
- EOEvent
    - `id: String`—이벤트 식별자
    - `title: String`—이벤트 제목
    - `description: String`—이벤트 설명
    - `link: URL?`—해당 이벤트에 대한 엔드 포인트의 전체 링크 주소
    - `closeDate: Date?`—이벤트가 끝났을 때 이를 'closed' 됐다고 하며, 이 경우 해당 필드는 날짜와 시간을 포함한다. 이벤트의 성격에 따라 해당 값은 정확하게 이벤트의 종료를 나타내지 않을 수 있다.
    - `locations: [EOLocation]?`—하나 또는 하나 이상의 위치와 특정 시각의 쌍
- EOLocation
    - `type: GeometryType`
    - `date: Date?`
    - `coordinates: Array<CLLocationCoordinate2D>`
- EOError
    - invalidURL(String)
    - invalidParameter(String, Any)
    - invalidJSON(String)
    - invalidDecoderConfiguration

### Generic API Request Technique

어떤 엔드 포인트로 데이터를 요청하든지, 그 핵심에는 공통적인 네트워크 요청 메카니즘이 존재한다. 

- 데이터를 요청한다.
- 성공적으로 응답 받은 데이터를 디코드한다.
- 이 과정에서 발생하는 모든 에러를 처리한다.

```swift
class EONET {
    static func request<T: Decodable>(...) -> Observable<T> 
        do {
            ... // Making URLRequest Process, Error-Prone
            return URLSession.shared.rx.response(request: request)
            .map({ ... // Decoding })
        } catch { return Observable.empty() }
    }
    ...
}
```

`URLSession.shared.rx.response(request:)`의 결과로 받은 응답을 제레릭 타입 `T`로 디코딩하여 이를 `Observable`로 반환한다. 

`URLRequest`를 만들고 응답을 받아 디코딩하기까지 일련의 과정에서 어떠한 에러가 발생하면, `catch` 블록에서 이를 처리한다. 위 메소드에서는 단순히 비어 있는 시퀀스를 반환한다. 

### Fetch Categories

첫 화면에 보여질 카테고리를 받아오는 메소드를 살펴본다. 해당 메소드는 다음과 같은 과정을 갖는다.

- 카테고리 API 엔드 포인트로부터 데이터를 요청한다.
- 결과를 적절히 매핑한다.
- 에러가 발생했다면, 빈 결과를 돌려준다.

```swift
class EONET {
    static var categories: Observable<EOCategory]> = {
        let request: Observable<[EOCategory]> = EONet.request(...)
        return request
            .map({ ... // Mapping })
            .catchErrorJustReturn([])
            .share(replay: 1, scope: .forever)
    }
}
```

request, 엄밀히 말하자면 네트워크 요청의 응답으로  받은 `Observable<[EOCateogry]>`를 반환할 때, 오퍼레이터 체인의 마지막에 `share(replay:scope:)` 오퍼레이터가 사용된 것을 볼 수 있다. 

이 오퍼레이터는 `단 하나의 subscription`을 공유하는 Observable 시퀀스를 반환하는데, 이후에 subscription이 발생할 때마다 마지막으로 받은 값을 즉시 replay한다. 

따라서 모든 구독자들은 categories로부터 반환 받은 Observable<[EOCategory]>를 구독할 때, 마지막으로 받은 값을 돌려 받는다. 

### Categories View Controller

CategoriesViewController는 EONET 서비스로부터 데이터를 가져와 이를 사용자에게 보여주는 역할을 한다. 위에서 이미 카테고리를 가져오는 메소드를 정의했으므로, 컨트롤러에서는 이를 활용한다.

```swift
class CategoriesViewController: UIViewController {
    let categories = BehaviorRelay<[EOCategory]>(value: [])
    let disposeBag = DisposeBag()
    ...
}
```

`[EOCategory]`를 유지하기 위해 `BehaviorRelay`를 선언한다. 이 categories를 아래처럼 구독하면 새로운 카테고리 배열이 들어올 때마다 유저 인터페이스를 업데이트 할 수 있다. 

```swift
class CategoriesViewController: UIViewController {
    ...
    override func viewDidLoad() {
        super.viewDidLoad()
        
        categories
            .asObservable()
            .subscribe(onNext: { ... // UI UPDATE })
            .disposed(by: disposeBag)
    }
}
```

하지만 이 상태에서는 아무 일도 일어나지 않는다. BehaviorRelay의 기본 값으로 주어진 빈 배열만 발생한다. 

EONET 서비스에게 데이터를 요청하고, 이를 categories에 보내어 유저 인터페이스가 업데이트 되도록 해야 한다. 

```swift
class CategoriesViewController: UIViewController {
    ...
    func startDownload() {
        let eoCategories = EONET.categories
        eoCategories
            .bind(to: categories)
            .disposed(by: disposeBag)
    }
}
```

`bind(to:)`라는 새로운 오퍼레이터가 보이는데, 이는 리시버에 대한 새로운 구독을 만들고 이로부터 받는 모든 값들을 하나 이상의 `BehaviorRelay`로 보내는 역할을 한다. 

그러므로 여기에서 `bind(to:)`는 EONET의 `categories`, 즉 `Observable<[EOCategory]>`를 구독하는 동시에 이로부터 받는 모든 값들을 위에서 선언한 CategoriesViewController의 `BehaviorRelay categories` 로 보낸다. 

### Fetch Events

EONET API는 이벤트를 내려받기 위한 두개의 엔드 포인트를 제공하며 각각의 이벤트는 open과 closed로 구분된다. 

Open 이벤트는 말그대로 계속 진행 중임을 의미하고 Closed 이벤트는 이미 과거에 종료되었음을 의미한다. 

이벤트를 내려받기 위한 API 호출에서 고려할 수 있는 파라미터는 아래 두가지이다. 

- `days`: The number of *days* to go back in time to find events.
- `status`: The *open* or *closed* status of the events.

EONET API는 open 이벤트와 closed 이벤트에 대해 각각 호출할 것을 요구하고 있다. 유저 인터페이스에서 각각의 이벤트 종류에 대해 요청을 할 수도 있지만, 한번의 요청으로 두 이벤트 종류 모두 가져오는 것이 효율적일 것이다 .

따라서 여기에서는, 두가지 요청을 만들고 그 결과를 연결하여 유저 인터페이스로 돌려주도록 한다. 

먼저 다음은 유저 인터페이스에서 사용할 수 있는 메소드이다. 

```swift
class EONET {
    ...
    // 모든 이벤트를 가져오는 static method
    static func events(forLast days: Int) -> Observable<[EOEvent]> {
        // Download Open Events
        let openEvents = ...
        // Download Closed Events
        let closedEvents = ...
        
        return openEvents.concat(closedEvents)
    }
}
```

`openEvents`와 `closedEvents`에는 각각 후술할 `private` 메소드의 결과가 할당이 된다. 마지막으로 `concat` 오퍼레이터를 이용해 두 변수를 이어 붙인 `Observable<[EOEvent]>`를 반환하고 있다. 

```swift
class EONET {
    ...
    private static func events(forLast days: Int, closed: Bool) -> Observable<[EOEvent]> {
        let query: Query = [
            "days": days,
            "status": (closed ? "closed" : "open")
        ]
        let request: Observable<[EONET]> = EONet.request(...)
        return request.catchErrorJustReturn([])
    }
}
```

위 `private` 메소드는 `internal events` 메소드에서 `open`과 `closed` 이벤트를 각각 받아오기 위해 호출하는 메소드이다. 쿼리를 만들고 `request`를 호출하며, 그 결과를 반환하고 있다. 

### Categories View Controller Again

`CategoriesViewController`의 역할은 모든 카테고리를 가져오는 것 이외에, 각각의 카테고리에 대한 이벤트의 개수도 표현하는 것이라고 했다.

카테고리를 가져올 때 컨트롤러의 `startDownload()` 메소드를 이용했는데, 마찬가지로 이벤트를 가져오는 것도 해당 메소드에서 처리한다. 

```swift
func startDownload() {
    let eoCategories = EONET.categories
    let downloadedEvents = EONET.events(forLast: 360) // NEWLY ADDED
    ...
}
```

`eoCategories`에서는 위에서 살펴본 바와 같이 category API의 호출 결과 Observable을 반환 받으며 새롭게 추가된 `downloadedEvents`에서는 방금 작성한 events API의 호출 결과 Observable을 반환 받는다. 

`EOCategory`는 `[EOEvent]` 타입의 `events` 프로퍼티를 갖는다. 즉, `downloadedEvents`의 결과 `Observable<[EOEvent]>`를 `eoCategories`가 갖는 각각의 `EOCategory`의 `events`로 적절히 넣어줄 수 있을 것이다. 

```swift
func startDownload() {
    let eoCategories = EONET.categories
    let downloadedEvents = EONET.events(forLast: 360)
    let updatedCategories = Observable.combineLatest(eoCategories, downloadedEvents) {
        (categories, events) -> [EOCategory] in ... // NEWLY ADDED
    }
}
```

`combineLatest` 오퍼레이터가 사용된 것을 볼 수 있다. 여기에서 이 오퍼레이터는, `eoCategories`와 `downloadedEvents`를 결합해 새로운 `Observable<[EOCategory]>`를 만들어낸다. 결국 각각의 카테고리에 이벤트들이 들어간 새로운 카테고리 배열을 얻게 된다. 

combineLatest의 파라미터로 들어간 Observable 중 어느 것이라도 새로운 값을 가져올 때마다 클로져를 호출하는데, 여기에서 우리가 필요한 작업을 할 수 있다. 

```swift
func startDownload() {
    let eoCategories = EONET.categories
    let downloadedEvents = EONET.events(forLast: 360)
    let updatedCategories = Observable.combineLatest(eoCategories, downloadedEvents) {
        (categories, events) -> [EOCategory] in
        return categories.map { category in 
            var cat = category
            cat.events = events.filter {
                $0.categories.contains(where: { $0.id == category.id })
            }
            return cat
        }
    }
}
```

간단하다. 모든 이벤트를 탐색해 각각의 카테고리들 중, 현재 카테고리와 일치하는 그 이벤트를 모아 카테고리의 이벤트로 넣는다. 코드를 보면 이해가 쉬울 것이다. 효율성을 따지는 문제는 범위를 벗어나지만, 얼핏 보더라도 컬렉션의 전체를 탐색하는 코드가 세가지 보인다.

마지막으로, 이 결과들을 컨트롤러가 가지고 있는 categories와 묶기 위한 코드를 작성한다. 

```swift
eoCategories
    .concat(updatedCategories)
    .bind(to: self.categories)
    .disposed(by: disposeBag)
```

### Minor Improvement: Downloading In Parallel

open 이벤트와 closed 이벤트를 가져올 때, concat 오퍼레이터를 이용해서 작성했다. 이는 첫 Observable이 끝난 뒤 다음 Observable을 실행하는데, 순차적으로 내려받기보다 병렬로 내려받으면 더 효율적일 것이다. 

```swift
class EONET {
    ...
    // 모든 이벤트를 가져오는 static method
    static func events(forLast days: Int) -> Observable<[EOEvent]> {
        // Download Open Events
        let openEvents = ...
        // Download Closed Events
        let closedEvents = ...
        
        return Observable.of(openEvents, closedEvents)
            .merge()
            .reduce([], accumulator: +)
    }
}
```

### Events View Controller

사용자가 하나 이상의 이벤트를 가진 카테고리를 선택하면, 해당 카테고리의 모든 이벤트 목록을 보여줘야 한다. 그 역할은 `EventsViewController`가 가진다.

이 컨트롤러는 카테고리의 이벤트를 유지하기 위해 `BehaviorRelay<[EOEvent]>` 타입의 `events` 프로퍼티를 갖는다. 그리고 이를 구독하여 새로운 이벤트가 들어올 때 유저 인터페이스를 업데이트 하도록 한다. 

```swift
class EventsViewController: UIViewController {
    let events = BehaviorRelay<[EOEvent]>(value: [])
    let disposeBag = DisposeBag()

    override func viewDidLoad() {
        self.view.viewDidLoad()

        events.asObservable()
            .subscribe(onNext: ... )
            .disposed(by: disposeBag)
    }
}
```

### Wiring The Days Selector

`EventsViewController`의 뷰는 `UISlider`를 갖고 있다. 이 슬라이더는 0에서 360까지의 범위를 갖는데, 이는 표현될 이벤트들의 최대 기간이다. 

UISlider의 값에 따라 유저 인터페이스를 업데이트 하려면 다음의 과정을 거치면 된다.

Updating: UISlider's Value (by an user) → Filtering: Events By New Value → Updating: User Interface

먼저 UISlider의 값을 업데이트하는 과정이다. 

```swift
class EventsViewController: UIViewController {
    let days = BehaviorRelay<Int>(value: 360)

    func handleSliderAction(slider: UISlider) {
        days.accept(Int(slider.value))
    }
    ...
}
```

UISlider의 값이 업데이트 되었으므로, 어디에선가 이 값에 따라 이벤트를 다시 분류해야 한다. 그리고 이 이벤트들을 유지해야 한다. 

```swift
class EventsViewController: UIViewController {
    let days = BehaviorRelay<Int>(value: 360)

    func handleSliderAction(slider: UISlider) {
        days.accept(Int(slider.value))
    }

    let filteredEvents = BehaviorRelay<[EOEvent]>(value: [])
    
    override func viewDidLoad() {
        self.viewDidLoad()
        
        Observable.combineLatest(days, events) { days, events -> [EOEvent] in ... })
            .bind(to: filteredEvents)
            .disposed(by: disposeBag)
    }
}
```

그리고 마지막으로 filteredEvents를 구독하여 유저 인터페이스를 업데이트하도록 하면 완성된다. 

```swift
class EventsViewController: UIViewController {
    let days = BehaviorRelay<Int>(value: 360)

    func handleSliderAction(slider: UISlider) {
        days.accept(Int(slider.value))
    }

    let filteredEvents = BehaviorRelay<[EOEvent]>(value: [])
    
    override func viewDidLoad() {
        self.viewDidLoad()
        
        Observable.combineLatest(days, events) { days, events -> [EOEvent] in ... })
            .bind(to: filteredEvents)
            .disposed(by: disposeBag)

        filteredEvents.asObservable()
        .subscribe(onNext: ...)
    }
}
```

이제 사용자가 카테고리를 선택하면 해당 카테고리의 이벤트를 보여줄 수 있고, 슬라이더를 조절함으로써 해당 날짜까지의 이벤트만 보여지도록 할 수 있다.

### Splitting Event Downloads

지금까지는 이벤트를 한번에 가져오는 API를 호출했는데, 카테고리별로 나누어 내려받을 수도 있다. 

- 모든 카테고리를 요청한다.
- 각각의 카테고리에 대한 이벤트를 요청한다.
- 요청한 이벤트를 받으면 기존의 카테고리와 유저 인터페이스를 업데이트한다.
- 위 두 과정을, 모든 카테고리에 대해서 반복한다.

먼저, EONET 서비스 클래스의 기존 이벤트 API 호출 메소드를 수정해야 한다. 

```swift
class EONET {
    ...
    FROM
    // 모든 이벤트를 가져오는 static method
    static func events(forLast days: Int) -> Observable<[EOEvent]> {
        // Download Open Events
        let openEvents = ...
        // Download Closed Events
        let closedEvents = ...
        
        return Observable.of(openEvents, closedEvents)
            .merge()
            .reduce([], accumulator: +)
    }
    TO
    static func events(forLast days: Int, category: EOCategory) -> Observable<[EOEvent]> {
        ...
    }
}
```

EONET 서비스의 메소드가 변경되었으니 이를 호출하는 곳에서도 수정을 해줘야 한다. 

```swift
class CategoriesViewController: UIViewController {
    ...
    func startDownload() {
        ...
        let eoCategories = EONET.categories
        let downloadedEvents = eoCategories
            .flatMap { 
                return Observable.from($0.map {
                    return EONET.events(forLast: 360, category: $0)
                })
            }
            .merge()
        
        let updatedCategories = eoCategories.flatMap { categories in
            downloadedEvents.scan(categories) { (updated, events) in
                return updated.map { category in
                    let eventsForCategory = EONET.filteredEvents(events: events, forCategory: category)
                    if !eventsForCategory.isEmpty {
                        var _category = category
                        _category.events = _category.events + eventsForCategory
                        return _category
                    }
                    return cateogry
                }
            }
        }
    }
}
```

`downloadedEvents`는 `eoCategories`의 결과인 `Observable[EOCategories]`를 받아 `flatMap` 오퍼레이터를 통해 `Observable<Observable[EOEvents]>`로 매핑한다. 그리고 `merge` 오퍼레이터로 이 결과들을 하나의 이벤트 배열 `Observable`로 합친다. 

## What I've Learned

### Foundation

- URL—Instance Method—appendingPathComponent(_:)

    ```swift
    func appendingPathComponent(_ pathComponent: String) -> URL
    ```

    기존의 `URL`에 주어진 `pathComponent`를 덧붙여 반환한다.

- URLComponents—Initializer—init?(url: URL, resolvingAgainstBaseURL: Bool)

    ```swift
    init?(url: URL, resolvingAgainstBaseURL resolve: Bool)
    ```

    `URLComponents`는 URL을 분석하고 이를 이루는 요소들로 URL을 구성한다. 

    `RFC 3986`에 따라 URL을 분석하고 구성하는데, 이는 이전의 RFC를 따르는 `URL`과는 조금 다르게 동작한다. 하지만 `URLComponents`의 내용을 바탕으로 쉽게 `URL`을 알 수 있다. 

### RxSwift

- URLSession.shared.rx
- share(replay:scope:)
- bind(to:)
- combineLatest
